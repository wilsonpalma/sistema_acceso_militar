from django.urls import path
from .views import AccessInfoView, ZoneListAPI

urlpatterns = [
    path("access-info/", AccessInfoView.as_view(), name="access_info"),
    path("zones/", ZoneListAPI.as_view(), name="api_zones"),
]
