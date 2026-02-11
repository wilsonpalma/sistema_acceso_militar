from rest_framework import serializers
from .models import Personnel, RestrictedZone

""" class PersonnelSerializer(serializers.ModelSerializer):
    class Meta:
        model = Personnel
        fields = '__all__'
# serializers.py
from rest_framework import serializers
from django.utils import timezone
from .models import Personnel, Rank, Unit, ClearanceLevel, Permission, RestrictedZone, PersonnelPermission, SpecialAccessGrant
 """
class RankSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    code = serializers.CharField()
    name = serializers.CharField()
    level = serializers.IntegerField()

class UnitSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    code = serializers.CharField()
    name = serializers.CharField()

class ClearanceSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    name = serializers.CharField()
    level_value = serializers.IntegerField()

class PermissionOutSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    code = serializers.CharField()
    name = serializers.CharField()
    expires_at = serializers.DateTimeField(allow_null=True)

class ZonePermissionReqSerializer(serializers.Serializer):
    permission_id = serializers.IntegerField()
    code = serializers.CharField()
    required = serializers.BooleanField()

class ZoneOutSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    code = serializers.CharField()
    name = serializers.CharField()
    min_rank_level = serializers.IntegerField(allow_null=True)
    required_clearance_name = serializers.CharField(allow_null=True)
    requires_special_permission = serializers.BooleanField()
    permission_requirements = ZonePermissionReqSerializer(many=True)

class EvidenceSerializer(serializers.Serializer):
    check = serializers.CharField()
    passed = serializers.BooleanField()
    # puede incluir campos extra (value, required, matching_permissions)
    value = serializers.IntegerField(required=False)
    required = serializers.IntegerField(required=False)
    matching_permissions = serializers.ListField(child=serializers.IntegerField(), required=False)

class ValidationSerializer(serializers.Serializer):
    allowed = serializers.BooleanField()
    reason = serializers.CharField()
    evidence = EvidenceSerializer(many=True)

class AccessInfoSerializer(serializers.Serializer):
    service_number = serializers.CharField()
    badge_id = serializers.CharField(allow_null=True)
    first_name = serializers.CharField()
    last_name = serializers.CharField()
    rank = RankSerializer()
    unit = UnitSerializer(allow_null=True)
    clearance = ClearanceSerializer(allow_null=True)
    permissions = PermissionOutSerializer(many=True)
    special_access = serializers.DictField(allow_null=True)  # o un serializer específico
    zone = ZoneOutSerializer()
    validation = ValidationSerializer()


# A continuacion configuracion para mostrar las zonas

class ZonePermissionRequirementSimpleSerializer(serializers.Serializer):
    permission_id = serializers.IntegerField()
    code = serializers.CharField()
    name = serializers.CharField()
    required = serializers.BooleanField()
    notes = serializers.CharField(allow_null=True)

class ZoneSerializer(serializers.ModelSerializer):
    required_clearance_name = serializers.CharField(source="required_clearance.name", read_only=True)
    permission_requirements = serializers.SerializerMethodField()

    class Meta:
        model = RestrictedZone
        fields = (
            "id",
            "code",
            "name",
            "location_description",
            "min_rank_level",
            "required_clearance_name",
            "requires_special_permission",
            "capacity",
            "active",
            "notes",
            "permission_requirements",
        )

    def get_permission_requirements(self, obj):
        # evita N+1: usa select_related/ prefetch en la vista para producir mejor rendimiento
        reqs = getattr(obj, "permission_requirements_cache", None)
        if reqs is None:
            # fallback si no se pasó cache desde la vista
            reqs = obj.permission_requirements.select_related("permission").all()
        out = []
        for r in reqs:
            out.append({
                "permission_id": r.permission.id,
                "code": r.permission.code,
                "name": r.permission.name,
                "required": r.required,
                "notes": r.notes
            })
        return out


