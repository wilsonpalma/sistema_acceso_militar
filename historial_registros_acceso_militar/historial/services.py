# historial/services.py
import requests
from requests.exceptions import RequestException
from django.core.cache import cache
from django.conf import settings
from django.utils import timezone

from .mongo import access_attempts_col

# keys y timeouts
ZONES_CACHE_KEY = "external_zones_list"
ZONES_CACHE_TTL = getattr(settings, "ZONES_CACHE_TTL", 300)  # 5 min por defecto
ZONES_SERVICE_URL = getattr(settings, "ZONES_SERVICE_URL", "http://127.0.0.1:8000/ws/zones/")
ACCESS_INFO_URL = getattr(settings, "ACCESS_INFO_URL", "http://127.0.0.1:8000/ws/access-info/")

def fetch_zones():
    """
    Devuelve lista de zonas (normalizadas) consultando el servicio MySQL.
    Usa cache para evitar peticiones repetidas.
    """
    zones = cache.get(ZONES_CACHE_KEY)
    if zones is not None:
        return zones

    try:
        resp = requests.get(ZONES_SERVICE_URL, timeout=5)
        resp.raise_for_status()
        data = resp.json()
        # Normalizar: id -> str, incluir code/name/min_rank...
        out = []
        for z in (data or []):
            out.append({
                "id": str(z.get("id")),
                "code": z.get("code"),
                "name": z.get("name"),
                "min_rank_level": z.get("min_rank_level"),
                "required_clearance_name": z.get("required_clearance_name"),
                "requires_special_permission": bool(z.get("requires_special_permission")),
            })
        cache.set(ZONES_CACHE_KEY, out, ZONES_CACHE_TTL)
        return out
    except RequestException as exc:
        # Si falla el servicio remoto devolvemos lista vacía
        # En producción loggear el error
        return []

def query_access_info(service_number=None, badge_id=None, zone_code=None):
    """
    Llamada al WS /access-info/ con badge_id o service_number y zone_code.
    Devuelve dict JSON si OK, None/raise si error.
    """
    if not zone_code or (not service_number and not badge_id):
        raise ValueError("zone_code y badge_id o service_number son requeridos")

    params = {"zone_code": zone_code}
    if service_number:
        params["service_number"] = service_number
    else:
        params["badge_id"] = badge_id

    try:
        resp = requests.get(ACCESS_INFO_URL, params=params, timeout=5)
        # devolver el json aunque sea 404/400 para que el caller decida
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        return resp.json()
    except RequestException as exc:
        # En producción: loguear exc
        raise

def save_access_attempt(access_info, attempt_meta):
    """
    Inserta en Mongo un documento de intento combinando:
    - access_info: respuesta del WS (persona, zone, validation, permissions...)
    - attempt_meta: { timestamp, gate_id, device, ip, processed_by }
    Devuelve el resultado de insert_one.
    """
    now = timezone.now()
    doc = {
        "personnel": access_info.get("service_number") or access_info.get("badge_id") or None,
        "personnel_full": {
            "service_number": access_info.get("service_number"),
            "badge_id": access_info.get("badge_id"),
            "first_name": access_info.get("first_name"),
            "last_name": access_info.get("last_name"),
            "rank": access_info.get("rank"),
            "unit": access_info.get("unit"),
            "clearance": access_info.get("clearance"),
            "permissions": access_info.get("permissions"),
            "special_access": access_info.get("special_access")
        },
        "zone": access_info.get("zone"),
        "validation": access_info.get("validation"),
        "attempt": {
            # timestamp debe ser timezone-aware; lo guardamos en UTC
            "timestamp": attempt_meta.get("timestamp", now),
            "gate_id": attempt_meta.get("gate_id"),
            "device": attempt_meta.get("device"),
            "ip": attempt_meta.get("ip"),
        },
        "created_at": now,
        "processed_by": attempt_meta.get("processed_by", "web-ui"),
        # opcional: copia raw de access_info para auditoría
        "ws_response": access_info,
    }
    return access_attempts_col.insert_one(doc)
