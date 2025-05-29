# K3s Boat Monitoring

This repo is a quick guide for deploying a TIG stack and Prometheus as kubernetes pods:

- **Telegraf:** The agent for collecting and reporting metrics and data, so the receiver or collector of streaming telemetry data. It uses plug-ins for collecting and reporting metrics and can send the metrics to files, message queues, and other endpoints (*InfluxDB, Graphite, Kafka, MQTT*)
- **InfluxDB:** The time series database (TSDB) of the stack, it is optimized for fast, high-availability storage and retrieval of time series data
- **Prometheus:** A monitoring and alerting tool that uses *Prometheus Query Language (PromQL)* to retrieve and manipulate data for analysis and visualization. It collects (pulls) metrics from targets by scraping HTTP endpoints (for example an *snmp or node exporter*) and stores metrics as time-series data, recording information with a timestamp. It acts as a data source for other data visualization libraries like Grafana
- **Grafana:** Extracts data from databases like *InfluxDB* or *Prometheus*, performs basic or advanced data analytics, and creates dashboards

I use these tools to monitor the following things on my narrowboat:

- **Network health:** The [telegraf plugins](https://docs.influxdata.com/telegraf/v1/plugins/#input-plugins) will monitor ICMP (RTT, packet loss), HTTP (response times) and DNS sending data to InfluxDB
- **Phone (server):** Prometheus ([node-exporter](https://github.com/prometheus/node_exporter)) will monitor the phone (Kubernetes node) and monitoring applications (Kubernetes pods)
- **Teltonika router:** Prometheus ([snmp-exporter](https://github.com/prometheus/snmp_exporter/tree/main)) will monitor the routers health, cellular signal and traffic via SNMP
- **Victron equipment:** Victron Cerbo GX uses [MQTT](https://mqtt.org) to share data with Telegraf (and InfluxDB), the idea is to have local dashboard rather than relay on the Internet dependant Victron VRM

The below steps assume you already have a Kubernetes node setup with helm installed ready to deploy the pods on. I used an Android phone running K3s, see my [blog]() to learn how to do this or you want more explanations around the proceeding steps.

1. Clone the repo (`git clone https://github.com/sjhloco/k3s_boat_monitoring.git`) and edit the following attributes from the helm value files (in helm_values) and mqqt_keepalive.sh to match your local environment:
   - *influxdb_values.yaml:*
     - adminUser.password: To change the InfluxDB GUI admin user password (default is pa$$w0rd)
   - *telegraf_values.yaml:*
    - mqtt_consumer:.servers: Change 10.40.10.121 to the IP address of your Cerbo GX
    - mqtt_consumer.topics: Change 48e7da892735 to the MQTT ID of your Cerbo GX (check with [MQTT explorer](http://mqtt-explorer.com))
    - mqtt_consumer.topic_parsing.topic: Change 48e7da892735 to the MQTT ID of your Cerbo GX
   - *grafana_values.yaml:*
    - adminPassword: To change the Grafana GUI admin user password (default is pa$$w0rd)
   - *snmp.yml:*
    - auths.snmpv2_com.community: Change to be the same SNMP community value configured on your Teltonika RUT950 router
   - *prometheus_values.yaml:*
    - extraScrapeConfigs.job_name.snmp_teltonika.static_configs.targets: Your Teltonika RUT950 router IP address
   - *mqtt_keepalive.sh:*
     - Replace 10.40.10.121 and 48e7da892735 with your Cerbo GX IP address and MQTT ID
     - 
Below are a few attributes that are optional, can be changed if you wish to customise the deployment further (but dont have to be)

 - Influxdb: organization, bucket, token
 - telegraf: organization, bucket, token, hostname (as seen in influxdb)
 - grafana: dbName (bucket),  httpHeaderValue1 (token)

2. Copy all the files over to your K3s node

```bash
scp -r helm_charts user@x.x.x.x:
scp mqtt_keepalive.sh user@x.x.x.x:/etc/periodic/daily/mqtt_keepalive.sh
```

3. On the K3s node install *mosquitto-clients* (below cmd is for Apline-linux), make the mqtt_keepalive.sh executable and add the *crond* service to the boot sequence so it starts automatically at bootup.

```bash
sudo chmod +x /etc/periodic/daily/mqtt_keepalive.sh
sudo rc-update add crond
sudo rc-service crond start
rc-service crond status
```

4. Add and update helm chart repos and create a K3s namespace

```bash
helm repo add influxdata https://helm.influxdata.com/
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 
helm repo update

kubectl create namespace monitoring
```

5. Deploy the pods and create services where necessary for external access to GUI (influxdb, promethues, grafana)

```bash
helm install infl influxdata/influxdb2 -f helm_values/influxdb_values.yaml --namespace monitoring
helm install tele influxdata/telegraf -f helm_values/telegraf_values.yaml -n monitoring
helm install graf grafana/grafana -f helm_values/grafana_values.yaml -n monitoring
helm install prom prometheus-community/prometheus -f helm_values/prometheus_values.yaml -n monitoring
helm install snmp prometheus-community/prometheus-snmp-exporter --set-file config=helm_values/snmp.yml -n monitoring

kubectl expose service infl-influxdb2 --type=NodePort --target-port=8086 --name=infl-influxdb2-ext --namespace monitoring
kubectl expose service graf-grafana --type=NodePort --target-port=3000 --name=graf-grafana-ext --namespace monitoring
kubectl expose service prom-prometheus-server --type=NodePort --target-port=9090 --name=prom-prometheus-server-ext -n monitoring
kubectl expose service snmp-prometheus-snmp-exporter --type=NodePort --target-port=9116 --name=snmp-prometheus-snmp-exporter-ext -n monitoring
```

Once everything has been deployed is deployed should see all the Pods up and the appropriate NodePort Services created to allow external access to GUIs

```bash
kubectl get pods -n monitoring
kubectl get services  -n monitoring
```

If any of the Pods are not up use the pod Name from *get pods* in the following commands to check Pod status, logs as well as the application logs.

```bash
kubectl describe pod POD_NAME --namespace kube-system
kubectl logs POD_NAME -n monitoring
```

5. Add a SNMP community on the Teltonika RUT950 to match that in the snmp.yaml file and enable *MQTT on LAN* on the Cerbo GX

You should now be able to log into the following GUIs remotely using the NK3s IP and NodePort (got from *get services*), so `http://k3s_node_ip:nodePort`

- InfluxDB: Use admin/pa$$w0rd to login, can view the data received from Telegraf Database bucket (stesworld)
- snmp-exporter: No username/password, can see the configuration and the metrics of snmp-exporter itself
- Prometheus: No username/password, under Target Health can see health of all metric sources that prometheus is scraping from
- Grafana: Use admin/pa$$w0rd to login, under Connections > Data sources > influxdb click test to proved it is receiving measurement stats from influxdb. Download my [custom dashboards](https://github.com/sjhloco/grafana_dashboards) and import setting the data source for each when you do so  
