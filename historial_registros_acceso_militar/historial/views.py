# historial/views.py
from django.shortcuts import render
from datetime import datetime
from .mongo import access_attempts_col
# from .services import estudiante_existe
from bson import ObjectId

# estos imports a continuacion son para el registro de militares
from django.shortcuts import redirect
from django.urls import reverse
from django.contrib import messages
from django.utils import timezone
from .services import fetch_zones, query_access_info, save_access_attempt

""" def registrar_evento(request):
    eventos = list(eventos_col.find())

    for evento in eventos:
        evento["id"] = str(evento["_id"])
        evento["nombre"] = evento.get("nombre") or evento.get("nombre_evento") or evento.get("titulo")

    
    mensaje = ""

    if request.method == "POST":
        cedula = request.POST.get("cedula")
        evento_id = request.POST.get("evento")


        if estudiante_existe(cedula):
            access_attempts_col.insert_one({
                "evento_id": ObjectId(evento_id),
                "cedula_estudiante": cedula,
                "fecha_inscripcion": datetime.now()
            })
            mensaje = "Inscripción realizada con éxito"
        else:
            mensaje = "El estudiante NO existe en el sistema académico"
    
    return render(request, "registrar.html", {
        "eventos": eventos,
        "mensaje": mensaje
    })
 """
def graficas(request):
    return render(request, 'graficas.html')






# a continuacion funciones relacionadas con el registro de militares
def _get_client_ip(request):
    # método simple; en producción considerar X-Forwarded-For
    xff = request.META.get("HTTP_X_FORWARDED_FOR")
    if xff:
        return xff.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR")

def registrar_acceso(request):
    """
    Formulario que:
    - obtiene la lista de zonas desde el servicio MySQL (fetch_zones)
    - permite elegir entre badge_id o service_number
    - en POST llama a /ws/access-info/?... y guarda el intento en Mongo
    """
    zonas = fetch_zones()

    if request.method == "POST":
        id_type = request.POST.get("id_type")  # 'badge' o 'service'
        id_value = request.POST.get("id_value", "").strip()
        zone_code = request.POST.get("zone_code")
        gate_id = request.POST.get("gate_id", "GATE-1").strip()
        device = request.POST.get("device", "web-ui").strip()
        ip = _get_client_ip(request)
        processed_by = request.user.username if request.user.is_authenticated else "web-ui"

        # validaciones básicas
        if id_type not in ("badge", "service"):
            messages.error(request, "Tipo de identificación inválido.")
            return redirect(reverse("historial:registrar_acceso"))

        if not id_value:
            messages.error(request, "Debe ingresar el valor para la identificación seleccionada.")
            return redirect(reverse("historial:registrar_acceso"))

        if not zone_code:
            messages.error(request, "Debe seleccionar una zona.")
            return redirect(reverse("historial:registrar_acceso"))

        # llamar al WS
        try:
            if id_type == "service":
                access_info = query_access_info(service_number=id_value, zone_code=zone_code)
            else:
                access_info = query_access_info(badge_id=id_value, zone_code=zone_code)
        except Exception as exc:
            messages.error(request, f"Error comunicándose con el servicio de autenticación: {str(exc)}")
            return redirect(reverse("historial:registrar_acceso"))

        if access_info is None:
            # el WS devolvió 404 o no encontró al militar
            messages.error(request, "No se encontró al militar en el servicio de autenticación.")
            return redirect(reverse("historial:registrar_acceso"))

        # access_info contiene la evaluación (validation) — guardamos intento
        attempt_meta = {
            "timestamp": timezone.now(),
            "gate_id": gate_id,
            "device": device,
            "ip": ip,
            "processed_by": processed_by,
        }

        inserted = save_access_attempt(access_info, attempt_meta)

        # Mensaje según validación
        validation = access_info.get("validation", {})
        allowed = validation.get("allowed", False)
        reason = validation.get("reason", "no_reason")

        if allowed:
            messages.success(request, f"Acceso PERMITIDO ({reason}). Intento registrado en Mongo: {inserted.inserted_id}")
        else:
            messages.warning(request, f"Acceso DENEGADO ({reason}). Intento registrado en Mongo: {inserted.inserted_id}")

        return redirect(reverse("historial:registrar_acceso"))

    # GET: render form
    return render(request, "registro_acceso.html", {
        "zonas": zonas
    })
