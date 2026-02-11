# uso
# generar 1000 documentos
# python manage.py generate_access_attempts --n 1000 --output ./output.json --seed 42

# ws/management/commands/generate_access_attempts.py
from django.core.management.base import BaseCommand
from django.utils import timezone
from django.db.models import Q

import random
import json
from datetime import timedelta

# Ajusta el import si tu app no se llama 'ws'
from ws.models import (
    Personnel,
    RestrictedZone,
    PersonnelPermission,
    ZonePermissionRequirement,
    SpecialAccessGrant,
    Permission,
)

# Opcional: si quieres nombres realistas
try:
    from faker import Faker
    fake = Faker()
except Exception:
    fake = None

# Mapeo local de clearance names (si quieres usar el nombre -> valor)
# Si en tu DB clearance_levels ya tienen level_value, no necesitas esto.
# CLEARANCE_LEVELS = {"CONFIDENTIAL":1, "SECRET":2, "TOP_SECRET":3}

def iso_z(dt):
    if dt is None:
        return None
    return dt.astimezone(timezone.utc).replace(tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")

class Command(BaseCommand):
    help = "Genera un JSON array con registros sintéticos de access_attempts usando datos reales de MySQL."

    def add_arguments(self, parser):
        parser.add_argument("--n", type=int, default=500, help="Cantidad de documentos a generar.")
        parser.add_argument("--output", type=str, default="access_attempts_from_mysql.json", help="Archivo JSON de salida.")
        parser.add_argument("--seed", type=int, default=None, help="Seed para reproducibilidad.")
        parser.add_argument("--start-days", type=int, default=365, help="Rango: cantidad de días atrás desde hoy para generar timestamps.")
        parser.add_argument("--only-active-zones", action="store_true", help="Usar solo zonas con active=True.")
        parser.add_argument("--only-personnel-active", action="store_true", help="Preferir personal con status='active' (no exclusivo).")

    def handle(self, *args, **options):
        n = options["n"]
        out_file = options["output"]
        seed = options["seed"]
        start_days = options["start_days"]
        only_active_zones = options["only_active_zones"]
        only_personnel_active = options["only_personnel_active"]

        if seed is not None:
            random.seed(seed)
            if fake:
                fake.seed_instance(seed)

        now = timezone.now()
        start_dt = now - timedelta(days=start_days)

        # cargar zonas
        if only_active_zones:
            zonas_qs = RestrictedZone.objects.filter(active=True).select_related("required_clearance")
        else:
            zonas_qs = RestrictedZone.objects.all().select_related("required_clearance")
        zonas = list(zonas_qs)

        if not zonas:
            self.stderr.write("No se encontraron zonas en la BD. Abortar.")
            return

        # cargar personnel
        if only_personnel_active:
            personnel_qs = Personnel.objects.filter(status="active").select_related("rank", "clearance", "unit")
        else:
            personnel_qs = Personnel.objects.all().select_related("rank", "clearance", "unit")
        personnel_list = list(personnel_qs)

        if not personnel_list:
            self.stderr.write("No se encontraron personnel en la BD. Abortar.")
            return

        docs = []
        for i in range(n):
            # elegir al azar
            p = random.choice(personnel_list)
            z = random.choice(zonas)

            # obtener permisos activos del personal (no expirados)
            now_check = timezone.now()
            perms_qs = PersonnelPermission.objects.filter(
                personnel=p,
                active=True
            ).filter(Q(expires_at__isnull=True) | Q(expires_at__gt=now_check)).select_related("permission")
            perm_ids = set([pp.permission.id for pp in perms_qs if getattr(pp, "permission", None) is not None])

            # requerimientos de la zona
            zreqs = list(ZonePermissionRequirement.objects.filter(zone=z).select_related("permission"))

            # comprobaciones
            exists = True
            status_ok = (p.status == "active")
            rank_level = getattr(p.rank, "level", None)
            min_rank = z.min_rank_level
            min_rank_pass = True if (min_rank is None) else (rank_level is not None and rank_level >= min_rank)

            required_clearance = getattr(z, "required_clearance", None)
            if required_clearance:
                p_clear_val = getattr(p.clearance, "level_value", None)
                clearance_pass = (p_clear_val is not None and p_clear_val >= required_clearance.level_value)
            else:
                clearance_pass = True

            # zone permission checks
            matching_permissions = []
            perm_ok = True
            required_ids = [r.permission_id for r in zreqs if r.required]
            for rid in required_ids:
                if rid in perm_ids:
                    matching_permissions.append(rid)
                else:
                    perm_ok = False

            # special access grants active
            special = SpecialAccessGrant.objects.filter(
                zone=z,
                personnel=p,
                status="active"
            ).filter(Q(expires_at__isnull=True) | Q(expires_at__gt=now_check)).first()

            if special:
                allowed = True
                reason = "special_grant"
            else:
                allowed = status_ok and min_rank_pass and clearance_pass and perm_ok
                if not status_ok:
                    reason = "status_not_active"
                elif min_rank is not None and not min_rank_pass:
                    reason = "rank_too_low"
                elif required_clearance and not clearance_pass:
                    reason = "clearance_insufficient"
                elif not perm_ok and z.requires_special_permission:
                    reason = "missing_zone_permission"
                else:
                    reason = "rank_ok_and_permission" if allowed else "denied"

            # evidencia
            evidence = [
                {"check": "exists", "passed": exists},
                {"check": "status_active", "passed": status_ok},
            ]
            if min_rank is not None:
                evidence.append({
                    "check": "min_rank", "passed": min_rank_pass,
                    "value": rank_level, "required": min_rank
                })
            if required_clearance:
                evidence.append({
                    "check": "clearance", "passed": clearance_pass,
                    "value": getattr(p.clearance, "level_value", None),
                    "required": required_clearance.level_value
                })
            evidence.append({
                "check": "zone_permission", "passed": perm_ok, "matching_permissions": matching_permissions
            })
            if special:
                evidence.append({"check": "special_access_grant", "passed": True, "grant_id": special.id})

            # permissions out (metadata)
            perms_out = []
            for pp in perms_qs:
                perm_obj = getattr(pp, "permission", None)
                if perm_obj:
                    perms_out.append({
                        "id": perm_obj.id,
                        "code": perm_obj.code,
                        "name": perm_obj.name,
                        "expires_at": iso_z(pp.expires_at) if getattr(pp, "expires_at", None) else None
                    })

            # generar timestamps aleatorios
            attempt_ts = start_dt + timedelta(seconds=random.randint(0, int((now - start_dt).total_seconds())))
            created_at = attempt_ts + timedelta(seconds=random.randint(1, 20))

            # construir personnel_full
            personnel_full = {
                "service_number": p.service_number,
                "badge_id": p.badge_id,
                "first_name": p.first_name,
                "last_name": p.last_name,
                "rank": {
                    "id": getattr(p.rank, "id", None),
                    "code": getattr(p.rank, "code", None),
                    "name": getattr(p.rank, "name", None),
                    "level": getattr(p.rank, "level", None),
                } if getattr(p, "rank", None) else None,
                "unit": {
                    "id": getattr(p.unit, "id", None),
                    "code": getattr(p.unit, "code", None),
                    "name": getattr(p.unit, "name", None),
                } if getattr(p, "unit", None) else None,
                "clearance": {
                    "id": getattr(p.clearance, "id", None),
                    "name": getattr(p.clearance, "name", None),
                    "level_value": getattr(p.clearance, "level_value", None),
                } if getattr(p, "clearance", None) else None,
                "permissions": perms_out,
                "special_access": {
                    "id": special.id,
                    "granted_by": getattr(special.granted_by, "id", None) if special and getattr(special, "granted_by", None) else None,
                    "granted_at": iso_z(special.granted_at) if special and getattr(special, "granted_at", None) else None,
                    "expires_at": iso_z(special.expires_at) if special and getattr(special, "expires_at", None) else None,
                    "status": special.status if special else None,
                    "reason": special.reason if special else None,
                } if special else None
            }

            # construir zona "simple" (no buscamos permission objects aquí, ya están en zreqs)
            zone_out = {
                "id": z.id,
                "code": z.code,
                "name": z.name,
                "min_rank_level": z.min_rank_level,
                "required_clearance_name": getattr(z.required_clearance, "name", None) if getattr(z, "required_clearance", None) else None,
                "requires_special_permission": z.requires_special_permission,
                "permission_requirements": [
                    {
                        "permission_id": r.permission.id if getattr(r, "permission", None) else r.permission_id,
                        "code": getattr(r.permission, "code", None) if getattr(r, "permission", None) else None,
                        "name": getattr(r.permission, "name", None) if getattr(r, "permission", None) else None,
                        "required": r.required,
                        "notes": r.notes
                    } for r in zreqs
                ]
            }

            doc = {
                # personnel marker
                "personnel": p.service_number or p.badge_id,
                "personnel_full": personnel_full,
                "zone": zone_out,
                "validation": {
                    "allowed": bool(allowed),
                    "reason": reason,
                    "evidence": evidence
                },
                "attempt": {
                    "timestamp": iso_z(attempt_ts),
                    "gate_id": random.choice(["GATE-1", "GATE-2", "MAIN-GATE", "SOUTH-GATE"]),
                    "device": random.choice(["terminal-v1", "terminal-v2", "mobile-reader"]),
                    "ip": f"10.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}"
                },
                "created_at": iso_z(created_at),
                "processed_by": random.choice(["script-generator", "guard-01", "guard-02"]),
                # opcional: incluir la respuesta "simulada" del WS
                "ws_response": {
                    "service_number": p.service_number,
                    "badge_id": p.badge_id,
                    "first_name": p.first_name,
                    "last_name": p.last_name,
                    "rank": personnel_full["rank"],
                    "unit": personnel_full["unit"],
                    "clearance": personnel_full["clearance"],
                    "permissions": perms_out,
                    "special_access": personnel_full["special_access"],
                    "zone": zone_out,
                    "validation": {
                        "allowed": bool(allowed),
                        "reason": reason,
                        "evidence": evidence
                    }
                }
            }

            docs.append(doc)

            if (i+1) % 1000 == 0:
                self.stdout.write(f"{i+1} documentos generados...")

        # escribir JSON array
        with open(out_file, "w", encoding="utf-8") as fh:
            json.dump(docs, fh, ensure_ascii=False, indent=2)

        self.stdout.write(self.style.SUCCESS(f"Generados {len(docs)} documentos en {out_file}"))
        self.stdout.write("")
        self.stdout.write("Ejemplo de import a MongoDB:")
        self.stdout.write(f" mongoimport --uri \"mongodb://localhost:27017\" --db historial_registros_acceso_militar --collection access_attempts --file {out_file} --jsonArray")
