from elasticsearch import Elasticsearch
import os

ELASTIC_URL = os.getenv("ELASTIC_URL", "http://localhost:9200")
es_client = Elasticsearch(ELASTIC_URL)
