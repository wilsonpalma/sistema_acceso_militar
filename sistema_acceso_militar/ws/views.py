# views.py
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from django.utils import timezone
from django.shortcuts import get_object_or_404
from .models import Personnel, RestrictedZone, PersonnelPermission, Permission, SpecialAccessGrant, ZonePermissionRequirement
from .serializers import AccessInfoSerializer
from datetime import datetime

from django.db import models

from rest_framework import generics
# from .models import RestrictedZone, ZonePermissionRequirement
from .serializers import ZoneSerializer



def evaluate_access(personnel, zone):
    """
    Devuelve dict con 'allowed', 'reason' y 'evidence' (lista).
    Lógica:
      - exists
      - status active
      - check min_rank_level (compara personnel.rank.level)
      - check clearance (compara clearance.level_value)
      - check zone permission requirements (perm asignadas y activas)
      - special_access overrides (si existe grant activo para esta persona y zona)
    """
    evidence = []
    # exists
    evidence.append({"check": "exists", "passed": True})
    # status active
    status_ok = (personnel.status == "active")
    evidence.append({"check": "status_active", "passed": status_ok})
    # min rank
    min_rank = zone.min_rank_level
    rank_level = getattr(personnel.rank, "level", None)
    if min_rank is not None:
        passed = (rank_level is not None and rank_level >= min_rank)
        evidence.append({"check": "min_rank", "passed": passed, "value": rank_level, "required": min_rank})
    # clearance
    required_clearance = zone.required_clearance
    if required_clearance:
        p_cl = getattr(personnel.clearance, "level_value", None)
        passed = (p_cl is not None and p_cl >= required_clearance.level_value)
        evidence.append({"check": "clearance", "passed": passed, "value": p_cl, "required": required_clearance.level_value})
    # zone permission requirements
    reqs = ZonePermissionRequirement.objects.filter(zone=zone)
    matching_permissions = []
    perms = PersonnelPermission.objects.filter(personnel=personnel, active=True)
    perm_ids = set(p.permission_id for p in perms)
    perm_ok = True
    for r in reqs:
        if r.required:
            if r.permission_id in perm_ids:
                matching_permissions.append(r.permission_id)
            else:
                perm_ok = False
    evidence.append({"check": "zone_permission", "passed": perm_ok, "matching_permissions": matching_permissions})
    # special access check (active grant for this zone and personnel)
    now = timezone.now()
    special = SpecialAccessGrant.objects.filter(zone=zone, personnel=personnel, status="active").filter(
        models.Q(expires_at__isnull=True) | models.Q(expires_at__gt=now)
    ).first()
    if special:
        evidence.append({"check": "special_access_grant", "passed": True, "grant_id": special.id})
        # override
        allowed = True
        reason = "special_grant"
    else:
        # aggregate results
        allowed = status_ok and (min_rank is None or (rank_level is not None and rank_level >= (min_rank or 0))) \
                  and (required_clearance is None or (getattr(personnel.clearance, "level_value", None) is not None and getattr(personnel.clearance, "level_value") >= required_clearance.level_value)) \
                  and perm_ok
        # decide a reason code for logging
        if not status_ok:
            reason = "status_not_active"
        elif min_rank is not None and not (rank_level is not None and rank_level >= min_rank):
            reason = "rank_too_low"
        elif required_clearance and not (getattr(personnel.clearance, "level_value", None) is not None and getattr(personnel.clearance, "level_value") >= required_clearance.level_value):
            reason = "clearance_insufficient"
        elif not perm_ok and zone.requires_special_permission:
            reason = "missing_zone_permission"
        else:
            reason = "rank_ok_and_permission" if allowed else "unspecified_denial"
    return {"allowed": allowed, "reason": reason, "evidence": evidence, "special_access": None if not special else {
        "id": special.id,
        "granted_by": special.granted_by_id,
        "granted_at": special.granted_at.isoformat() if special.granted_at else None,
        "expires_at": special.expires_at.isoformat() if special.expires_at else None,
        "status": special.status,
        "reason": special.reason
    }}

class AccessInfoView(APIView):
    """
    GET /api/access-info/?service_number=SN-20245&zone_code=CZ-01
    (o usar badge_id en vez de service_number)
    """
    def get(self, request, *args, **kwargs):
        svc = request.query_params.get("service_number")
        badge = request.query_params.get("badge_id")
        zone_code = request.query_params.get("zone_code")
        if not zone_code or (not svc and not badge):
            return Response({"detail":"zone_code and (service_number or badge_id) required"}, status=status.HTTP_400_BAD_REQUEST)

        # obtener persona
        if svc:
            personnel = get_object_or_404(Personnel, service_number=svc)
        else:
            personnel = get_object_or_404(Personnel, badge_id=badge)

        zone = get_object_or_404(RestrictedZone, code=zone_code)

        # permisos activos del personal (no expirados)
        now = timezone.now()
        perms_qs = PersonnelPermission.objects.filter(personnel=personnel, active=True).filter(
            models.Q(expires_at__isnull=True) | models.Q(expires_at__gt=now)
        ).select_related("permission")
        perms_out = [
            {
                "id": p.permission.id,
                "code": p.permission.code,
                "name": p.permission.name,
                "expires_at": p.expires_at.isoformat() if p.expires_at else None
            } for p in perms_qs
        ]

        # requirements for zone
        zreqs = list(ZonePermissionRequirement.objects.filter(zone=zone).select_related("permission"))
        zreqs_out = [{"permission_id": r.permission_id, "code": r.permission.code, "required": r.required} for r in zreqs]

        # evaluación
        eval_out = evaluate_access(personnel, zone)

        payload = {
            "service_number": personnel.service_number,
            "badge_id": personnel.badge_id,
            "first_name": personnel.first_name,
            "last_name": personnel.last_name,
            "rank": {
                "id": personnel.rank.id,
                "code": personnel.rank.code,
                "name": personnel.rank.name,
                "level": personnel.rank.level
            },
            "unit": None if not personnel.unit else {
                "id": personnel.unit.id, "code": personnel.unit.code, "name": personnel.unit.name
            },
            "clearance": None if not personnel.clearance else {
                "id": personnel.clearance.id, "name": personnel.clearance.name, "level_value": personnel.clearance.level_value
            },
            "permissions": perms_out,
            "special_access": eval_out.get("special_access"),
            "zone": {
                "id": zone.id, "code": zone.code, "name": zone.name,
                "min_rank_level": zone.min_rank_level,
                "required_clearance_name": zone.required_clearance.name if zone.required_clearance else None,
                "requires_special_permission": zone.requires_special_permission,
                "permission_requirements": zreqs_out
            },
            "validation": {
                "allowed": eval_out["allowed"],
                "reason": eval_out["reason"],
                "evidence": eval_out["evidence"]
            }
        }

        # serializar (opcional) para validar formato
        ser = AccessInfoSerializer(payload)
        return Response(ser.data, status=status.HTTP_200_OK)







# relacionado con Zone

class ZoneListAPI(generics.ListAPIView):
    """
    GET /api/zones/  -> devuelve lista de zonas activas
    """
    serializer_class = ZoneSerializer
    pagination_class = None  # sin paginación (devuelve todas; hay solo 8)

    def get_queryset(self):
        # traemos zonas activas y prefetch de requisitos para evitar N+1
        qs = RestrictedZone.objects.filter(active=True).select_related("required_clearance").order_by("code")
        return qs

    def list(self, request, *args, **kwargs):
        """
        Sobre-escribimos para inyectar los permission_requirements ya prefetched
        y así el serializer no haga queries adicionales.
        """
        queryset = self.get_queryset()
        # Prefetch manualmente los requisitos y adjuntarlos en un atributo para que el serializer los use
        zone_ids = [z.id for z in queryset]
        reqs = ZonePermissionRequirement.objects.filter(zone_id__in=zone_ids).select_related("permission")
        # construir mapa zone_id -> list(reqs)
        map_reqs = {}
        for r in reqs:
            map_reqs.setdefault(r.zone_id, []).append(r)
        # inyectar en cada instancia QuerySet (no recomendable en grandes volúmenes, pero ok para ~8 zonas)
        for z in queryset:
            setattr(z, "permission_requirements_cache", map_reqs.get(z.id, []))
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)