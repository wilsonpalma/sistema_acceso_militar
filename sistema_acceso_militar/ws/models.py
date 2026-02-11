# models.py
from django.db import models
from django.utils import timezone


class Rank(models.Model):
    id = models.AutoField(primary_key=True)
    code = models.CharField(max_length=16, unique=True)  # e.g. 'CPT'
    name = models.CharField(max_length=64)
    level = models.PositiveSmallIntegerField()  # comparable numeric value (higher = higher rank)
    description = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "ranks"
        ordering = ("-level",)

    def __str__(self):
        return f"{self.code} - {self.name}"


class ClearanceLevel(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=50, unique=True)  # e.g. 'CONFIDENTIAL'
    level_value = models.PositiveSmallIntegerField()
    description = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "clearance_levels"
        ordering = ("-level_value",)

    def __str__(self):
        return self.name


class Unit(models.Model):
    id = models.AutoField(primary_key=True)
    code = models.CharField(max_length=20, unique=True)  # 'U-005'
    name = models.CharField(max_length=128)
    parent_unit = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.SET_NULL, related_name="child_units"
    )
    location = models.CharField(max_length=128, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "units"

    def __str__(self):
        return f"{self.code} - {self.name}"


class Personnel(models.Model):
    STATUS_ACTIVE = "active"
    STATUS_SUSPENDED = "suspended"
    STATUS_RETIRED = "retired"
    STATUS_TERMINATED = "terminated"
    STATUS_CHOICES = [
        (STATUS_ACTIVE, "Active"),
        (STATUS_SUSPENDED, "Suspended"),
        (STATUS_RETIRED, "Retired"),
        (STATUS_TERMINATED, "Terminated"),
    ]

    id = models.AutoField(primary_key=True)
    service_number = models.CharField(max_length=32, unique=True)
    badge_id = models.CharField(max_length=64, unique=True, null=True, blank=True)
    first_name = models.CharField(max_length=80)
    last_name = models.CharField(max_length=80)
    dob = models.DateField(null=True, blank=True)
    rank = models.ForeignKey(Rank, on_delete=models.PROTECT, related_name="personnel")
    unit = models.ForeignKey(Unit, null=True, blank=True, on_delete=models.SET_NULL, related_name="personnel")
    clearance = models.ForeignKey(ClearanceLevel, null=True, blank=True, on_delete=models.SET_NULL, related_name="personnel")
    email = models.CharField(max_length=120, unique=True, null=True, blank=True)
    phone = models.CharField(max_length=30, null=True, blank=True)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_ACTIVE)
    enlisted_date = models.DateField(null=True, blank=True)
    discharge_date = models.DateField(null=True, blank=True)
    photo_url = models.CharField(max_length=255, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "personnel"
        indexes = [
            models.Index(fields=["rank"], name="idx_personnel_rank"),
            models.Index(fields=["unit"], name="idx_personnel_unit"),
            models.Index(fields=["clearance"], name="idx_personnel_clearance"),
        ]

    def __str__(self):
        return f"{self.service_number} - {self.first_name} {self.last_name}"


class Permission(models.Model):
    id = models.AutoField(primary_key=True)
    code = models.CharField(max_length=50, unique=True)  # e.g. 'ACCESS_SENSITIVE_SITE'
    name = models.CharField(max_length=100)
    description = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "permissions"

    def __str__(self):
        return self.code


class PersonnelPermission(models.Model):
    id = models.AutoField(primary_key=True)
    personnel = models.ForeignKey(Personnel, on_delete=models.CASCADE, related_name="permissions_assigned")
    permission = models.ForeignKey(Permission, on_delete=models.CASCADE, related_name="personnel_assignments")
    granted_by = models.ForeignKey(
        Personnel,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="granted_permissions",
        db_column="granted_by"
    )
    granted_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    reason = models.CharField(max_length=255, null=True, blank=True)
    active = models.BooleanField(default=True)

    class Meta:
        db_table = "personnel_permissions"
        constraints = [
            models.UniqueConstraint(fields=["personnel", "permission"], name="uk_person_perm")
        ]

    def __str__(self):
        return f"{self.personnel} → {self.permission} ({'active' if self.active else 'inactive'})"


class RestrictedZone(models.Model):
    id = models.AutoField(primary_key=True)
    code = models.CharField(max_length=32, unique=True)  # 'CZ-01'
    name = models.CharField(max_length=120)
    location_description = models.CharField(max_length=255, null=True, blank=True)
    min_rank_level = models.PositiveSmallIntegerField(null=True, blank=True)
    required_clearance = models.ForeignKey(ClearanceLevel, null=True, blank=True, on_delete=models.SET_NULL, related_name="zones")
    requires_special_permission = models.BooleanField(default=False)
    capacity = models.IntegerField(null=True, blank=True)
    active = models.BooleanField(default=True)
    notes = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "restricted_zones"
        indexes = [
            models.Index(fields=["min_rank_level"], name="idx_zone_minrank"),
            models.Index(fields=["required_clearance"], name="idx_zone_clearance"),
        ]

    def __str__(self):
        return f"{self.code} - {self.name}"


class ZonePermissionRequirement(models.Model):
    id = models.AutoField(primary_key=True)
    zone = models.ForeignKey(RestrictedZone, on_delete=models.CASCADE, related_name="permission_requirements")
    permission = models.ForeignKey(Permission, on_delete=models.CASCADE, related_name="zone_requirements")
    required = models.BooleanField(default=True)
    notes = models.CharField(max_length=255, null=True, blank=True)

    class Meta:
        db_table = "zone_permission_requirements"
        constraints = [
            models.UniqueConstraint(fields=["zone", "permission"], name="uk_zone_perm")
        ]

    def __str__(self):
        return f"{self.zone.code} requires {self.permission.code} ({'required' if self.required else 'optional'})"


class SpecialAccessGrant(models.Model):
    STATUS_ACTIVE = "active"
    STATUS_REVOKED = "revoked"
    STATUS_EXPIRED = "expired"
    STATUS_CHOICES = [
        (STATUS_ACTIVE, "Active"),
        (STATUS_REVOKED, "Revoked"),
        (STATUS_EXPIRED, "Expired"),
    ]

    id = models.AutoField(primary_key=True)
    zone = models.ForeignKey(RestrictedZone, on_delete=models.CASCADE, related_name="special_grants")
    personnel = models.ForeignKey(Personnel, on_delete=models.CASCADE, related_name="special_grants")
    granted_by = models.ForeignKey(
        Personnel,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="grants_made",
        db_column="granted_by"
    )
    granted_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    reason = models.CharField(max_length=255, null=True, blank=True)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_ACTIVE)

    class Meta:
        db_table = "special_access_grants"
        indexes = [
            models.Index(fields=["zone", "personnel"], name="idx_sag_zone_personnel")
        ]

    def __str__(self):
        return f"Grant {self.id}: {self.personnel} → {self.zone.code} ({self.status})"


class Badge(models.Model):
    STATUS_ISSUED = "issued"
    STATUS_REVOKED = "revoked"
    STATUS_LOST = "lost"
    STATUS_CHOICES = [
        (STATUS_ISSUED, "Issued"),
        (STATUS_REVOKED, "Revoked"),
        (STATUS_LOST, "Lost"),
    ]

    id = models.AutoField(primary_key=True)
    badge_code = models.CharField(max_length=64, unique=True)
    personnel = models.ForeignKey(Personnel, null=True, blank=True, on_delete=models.SET_NULL, related_name="badges")
    issued_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_ISSUED)

    class Meta:
        db_table = "badges"
        indexes = [
            models.Index(fields=["personnel"], name="idx_badge_personnel")
        ]

    def __str__(self):
        return self.badge_code
