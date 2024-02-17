cockroach init --insecure --host=us-east1:26257
cockroach sql --insecure --host=us-east1:26257 -e "SET CLUSTER SETTING cluster.organization = '${COMPANY}';SET CLUSTER SETTING enterprise.license = '${ENTKEY}';"
cockroach sql --insecure --host=us-east1:26257 -e "UPSERT INTO system.locations VALUES ('region','us-east',38.9072,-77.0369);"
