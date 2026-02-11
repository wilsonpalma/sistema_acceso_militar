# historial/mongo.py
from django.conf import settings
from pymongo import MongoClient

""" client = MongoClient("mongodb://localhost:27017/")
db = client["historial_registros_acceso_militar"]
 """
MONGO_URI = getattr(settings, "MONGO_URI", "mongodb://localhost:27017")
MONGO_DBNAME = getattr(settings, "MONGO_DBNAME", "historial_registros_acceso_militar")

client = MongoClient(MONGO_URI)
db = client[MONGO_DBNAME]

# colección donde guardaremos los intentos
access_attempts_col = db["access_attempts"]