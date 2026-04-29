class DisabledElasticsearchClient:
    def __getattr__(self, name):
        raise RuntimeError("Elasticsearch is disabled in this deployment")


es_client = DisabledElasticsearchClient()
