# historial/views_analytics.py
from django.http import JsonResponse
from django.shortcuts import render
from django.utils import timezone
from datetime import timedelta, datetime
from bson import ObjectId

from .mongo import access_attempts_col

# Helper: parse days param
def _get_start_date(request, default_days=30):
    try:
        days = int(request.GET.get("days", default_days))
        if days < 1:
            days = default_days
    except Exception:
        days = default_days
    start = datetime.utcnow() - timedelta(days=days)
    # PyMongo/Mongo expect naive UTC or timezone-aware; use naive UTC
    return start

# 1) Intentos por zona (barras)
def analytics_attempts_by_zone(request):
    start = _get_start_date(request)
    pipeline = [
        {"$addFields": {"ts": {"$toDate": "$attempt.timestamp"}}},
        {"$match": {"ts": {"$gte": start}}},
        {"$group": {"_id": "$zone.code", "count": {"$sum": 1}}},
        {"$sort": {"count": -1}}
    ]
    res = list(access_attempts_col.aggregate(pipeline))
    labels = [r["_id"] or "SIN_ZONA" for r in res]
    data = [r["count"] for r in res]
    return JsonResponse({"labels": labels, "datasets": [{"label": "Intentos", "data": data}]}, safe=False)

# 2) Permitidos vs Denegados (pie)
def analytics_allowed_vs_denied(request):
    start = _get_start_date(request)
    pipeline = [
        {"$addFields": {"ts": {"$toDate": "$attempt.timestamp"}}},
        {"$match": {"ts": {"$gte": start}}},
        {"$group": {"_id": "$validation.allowed", "count": {"$sum": 1}}},
        {"$sort": {"_id": -1}}
    ]
    res = list(access_attempts_col.aggregate(pipeline))
    # map True->Permitidos, False->Denegados
    mapping = {True: 0, False: 0, None: 0}
    for r in res:
        key = r["_id"]
        mapping[key] = r["count"]
    labels = ["Permitidos", "Denegados"]
    data = [mapping.get(True, 0), mapping.get(False, 0)]
    return JsonResponse({"labels": labels, "datasets": [{"data": data}]}, safe=False)

# 3) Serie temporal: intentos por día (línea)
def analytics_attempts_over_time(request):
    start = _get_start_date(request)
    pipeline = [
        {"$addFields": {"ts": {"$toDate": "$attempt.timestamp"}}},
        {"$match": {"ts": {"$gte": start}}},
        {"$project": {"day": {"$dateToString": {"format": "%Y-%m-%d", "date": "$ts"}}}},
        {"$group": {"_id": "$day", "count": {"$sum": 1}}},
        {"$sort": {"_id": 1}}
    ]
    res = list(access_attempts_col.aggregate(pipeline))
    # Fill missing dates between start..today with 0s (to keep chart continuous)
    labels = []
    data = []
    # build dictionary from res
    dmap = {r["_id"]: r["count"] for r in res}
    start_date = start.date()
    end_date = datetime.utcnow().date()
    cur = start_date
    while cur <= end_date:
        key = cur.isoformat()
        labels.append(key)
        data.append(dmap.get(key, 0))
        cur = cur + timedelta(days=1)
    return JsonResponse({"labels": labels, "datasets": [{"label": "Intentos/día", "data": data}]}, safe=False)

# 4) Top offenders (personnel con más intentos) - barras horizontales
def analytics_top_offenders(request):
    start = _get_start_date(request)
    try:
        limit = int(request.GET.get("limit", 10))
    except Exception:
        limit = 10
    pipeline = [
        {"$addFields": {"ts": {"$toDate": "$attempt.timestamp"}}},
        {"$match": {"ts": {"$gte": start}}},
        {"$group": {"_id": "$personnel_full.service_number", "count": {"$sum": 1}, "name": {"$first": "$personnel_full.first_name"}, "last": {"$first": "$personnel_full.last_name"}}},
        {"$sort": {"count": -1}},
        {"$limit": limit}
    ]
    res = list(access_attempts_col.aggregate(pipeline))
    labels = [ (r["_id"] or "UNK") + (f" — {r.get('name') or ''} {r.get('last') or ''}".strip()) for r in res ]
    data = [r["count"] for r in res]
    return JsonResponse({"labels": labels, "datasets": [{"label": "Intentos", "data": data}]}, safe=False)

# 5) Tasa de permitidos por rango (doughnut)
def analytics_allowed_rate_by_rank(request):
    start = _get_start_date(request)
    pipeline = [
        {"$addFields": {"ts": {"$toDate": "$attempt.timestamp"}}},
        {"$match": {"ts": {"$gte": start}}},
        {"$group": {"_id": {"rank": "$personnel_full.rank.code", "allowed": "$validation.allowed"}, "count": {"$sum": 1}}},
        {"$group": {"_id": "$_id.rank", "byAllowed": {"$push": {"k": {"$cond": ["$_id.allowed", "allowed", "denied"]}, "v": "$count"}}}},
        {"$project": {
            "allowed": {
                "$reduce": {
                    "input": "$byAllowed",
                    "initialValue": 0,
                    "in": { "$cond": [ { "$eq": ["$$this.k", "allowed"] }, "$$this.v", "$$value" ] }
                }
            },
            "denied": {
                "$reduce": {
                    "input": "$byAllowed",
                    "initialValue": 0,
                    "in": { "$cond": [ { "$eq": ["$$this.k", "denied"] }, "$$this.v", "$$value" ] }
                }
            }
        }},
        {"$sort": {"allowed": -1, "denied": -1}}
    ]
    res = list(access_attempts_col.aggregate(pipeline))
    labels = [r["_id"] or "SIN_RANGO" for r in res]
    # For doughnut we can show allowed counts or allowed percentage; here we send allowed counts
    data = [r.get("allowed", 0) for r in res]
    return JsonResponse({"labels": labels, "datasets": [{"label": "Permitidos (por rango)", "data": data}]}, safe=False)

# Dashboard view (render template with canvases)
def analytics_dashboard(request):
    # render the template; JS will fetch JSON from the endpoints below
    return render(request, "analytics_dashboard.html", {})



# a continuacion se definen funciones para mapeos de codigos con nombres o descripciones
def api_distinct_zones_from_mongo(request):
    """
    Devuelve lista de zonas únicas encontradas en access_attempts:
    [ { "code": "CZ-01", "name": "Centro de Control" }, ... ]
    """
    pipeline = [
        {"$match": {"zone.code": {"$exists": True}}},
        {"$group": {"_id": "$zone.code", "name": {"$first": "$zone.name"}}},
        {"$sort": {"_id": 1}}
    ]
    res = list(access_attempts_col.aggregate(pipeline))
    out = [{"code": r["_id"], "name": r.get("name")} for r in res if r["_id"]]
    return JsonResponse(out, safe=False)


def api_distinct_ranks_from_mongo(request):
    """
    Devuelve lista de rangos únicos (code + name) presentes en access_attempts:
    [ { "code": "CPT", "name": "Capitán" }, ... ]
    """
    pipeline = [
        {"$match": {"personnel_full.rank.code": {"$exists": True}}},
        {"$group": {"_id": "$personnel_full.rank.code", "name": {"$first": "$personnel_full.rank.name"}}},
        {"$sort": {"_id": 1}}
    ]
    res = list(access_attempts_col.aggregate(pipeline))
    out = [{"code": r["_id"], "name": r.get("name")} for r in res if r["_id"]]
    return JsonResponse(out, safe=False)