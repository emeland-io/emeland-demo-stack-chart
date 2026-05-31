# EmELand Demo Stack

This is a helm chart that should roll out a complete EmELand stack for demonstration purposes. You will need to provide a Kubernetes cluster to run the individual components

The following example uses a KinD cluster to provide the environment
```
kind create 
helm install emeland-demo-crd ./charts/emeland-demo-crd --namespace emeland-system --create-namespace
helm install emeland-demo ./charts/emeland-demo --namespace emeland-demo --create-namespace
```

# Stack Setup

The helm chart will roll out a number of components, either directly or from sub-charts:

- The 'emeland-demo-crd' chart allows the stable deployment of all the CRDs required for the full stack.
    - The modelsrv-k8s-sensor-crd
    - The grafana-crd
    - The prometheus-operator-crd
- This chart will set up the `Deployment` for the following components from prepared OCI images:
    1. **A modelsrv as the central server.** This will replaced with the the [web-server for the Web UI variant](https://github.com/emeland-io/modelsrv-web-ui-server), once it becomes available. It is configured to listen to events from the following two components
    2. **a container running the EmELand CLI tool.**. The container is running a shell and a user can attach to that shell via `kubectl attach`.
    3. **a container containing the git sensor demo data**: The container runs a git server
    4. **The Git sensor**. It will connect to the git server from the previous container.
- It will install the modelsrv Kubernetes sensor as a sub-chart. The sensor will scan the K8s cluster it is deployed in.
- It will install the kube-prometheus-stack chart as a sub-chart
    - It will install the a version of Grafana. If you want to have direct control of the version of the [Grafana chart](https://github.com/grafana-community/helm-charts/pkgs/container/helm-charts%2Fgrafana) from the Grafana community, you will need to configure this.

