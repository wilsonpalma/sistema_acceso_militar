from django.urls import path
from . import views
# from .views import registrar_evento, graficas

# a continuacion importamos lo relacionado con las analiticas
from .views_analytics import (
    analytics_attempts_by_zone,
    analytics_allowed_vs_denied,
    analytics_attempts_over_time,
    analytics_top_offenders,
    analytics_allowed_rate_by_rank,
    analytics_dashboard
)

app_name = "historial"

urlpatterns = [
    # path("registrar/", views.registrar_evento, name="registrar_evento"),
    path("graficas/", views.graficas, name="graficas"),
    path("registro-acceso/", views.registrar_acceso, name="registrar_acceso"),

    # endpoints para analíticas
    path("analytics/", analytics_dashboard, name="analytics_dashboard"),
    path("api/analytics/attempts_by_zone/", analytics_attempts_by_zone, name="api_attempts_by_zone"),
    path("api/analytics/allowed_vs_denied/", analytics_allowed_vs_denied, name="api_allowed_vs_denied"),
    path("api/analytics/attempts_over_time/", analytics_attempts_over_time, name="api_attempts_over_time"),
    path("api/analytics/top_offenders/", analytics_top_offenders, name="api_top_offenders"),
    path("api/analytics/allowed_rate_by_rank/", analytics_allowed_rate_by_rank, name="api_allowed_rate_by_rank"),
]


# A continuacion se añaden endpoints para mapeos de codigos con nombres o descripciones, que seran usados en las analiticas
# historial/urls.py (añadir entries)
from .views_analytics import api_distinct_zones_from_mongo, api_distinct_ranks_from_mongo

urlpatterns += [
    path("api/analytics/distinct_zones/", api_distinct_zones_from_mongo, name="api_distinct_zones_from_mongo"),
    path("api/analytics/distinct_ranks_from_mongo/", api_distinct_ranks_from_mongo, name="api_distinct_ranks_from_mongo"),
]


