
# Installation
## Build the Jenkins BlueOcean Docker Image
```
docker build -t myjenkins-blueocean:lts-jdk17 .
```

## Create the network 'jenkins'
```
docker network create jenkins
```

## Run the Container
### MacOS / Linux
```
docker run --name jenkins-blueocean --restart=on-failure --detach \
  --network jenkins --env DOCKER_HOST=tcp://docker:2376 \
  --env DOCKER_CERT_PATH=/certs/client --env DOCKER_TLS_VERIFY=1 \
  --publish 8080:8080 --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --volume jenkins-docker-certs:/certs/client:ro \
  myjenkins-blueocean:lts-jdk17
```

### Windows
```
docker run --name jenkins-blueocean --restart=on-failure --detach `
  --network jenkins --env DOCKER_HOST=tcp://docker:2376 `
  --env DOCKER_CERT_PATH=/certs/client --env DOCKER_TLS_VERIFY=1 `
  --volume jenkins-data:/var/jenkins_home `
  --volume jenkins-docker-certs:/certs/client:ro `
  --publish 8080:8080 --publish 50000:50000 myjenkins-blueocean:lts-jdk17
```


## Get the Password
```
docker exec jenkins-blueocean cat /var/jenkins_home/secrets/initialAdminPassword
```

## Connect to the Jenkins
```
https://localhost:8080/
```

## Installation Reference:
```
https://www.jenkins.io/doc/book/installing/docker/

```

## Chuyển Jenkins từ máy local lên dev server

`migrate-to-dev.sh` (chạy trên máy local đang chạy Jenkins):
```
bash migrate-to-dev.sh precheck   # kiểm tra 2 máy, không thay đổi gì
bash migrate-to-dev.sh image      # build image Jenkins trên dev (cố định version core 2.580.1)
bash migrate-to-dev.sh sync       # copy dữ liệu khi Jenkins local vẫn chạy (chạy lại bao nhiêu lần cũng được)
bash migrate-to-dev.sh cutover    # Prepare for Shutdown -> stop local -> sync lần cuối -> start trên dev -> đổi nginx
bash migrate-to-dev.sh rollback   # nếu lỗi: tắt Jenkins trên dev, trả nginx về local, start lại local
```
- Không copy `workspace/`, `caches/`, `war/`, `plugins/*/` (Jenkins tự tạo lại). Plugin giữ đúng version qua các file `.jpi`.
- Upload từ máy local lên dev chỉ khoảng 0.8 MB/s nên lần `sync` đầu mất khoảng 20–30 phút (rsync có nén). Nên chạy trong `tmux`; nếu đứt kết nối thì chạy lại, rsync sẽ chạy tiếp từ chỗ dừng.
- Lần sync đầu tiên, dữ liệu Jenkins cũ trên dev được giữ lại ở `/var/lib/docker/volumes/jenkins-data/_data.bak-<ts>`.
- Domain `jenkins.motcaigido.xyz` giữ nguyên, nên webhook và credentials không phải cấu hình lại.
- Trên dev, Jenkins chỉ listen `127.0.0.1:30006`, truy cập qua nginx.

## Local build agent (ưu tiên build ở máy local, fallback về dev server)

Kiến trúc:
- Dev server: Jenkins controller (`build.sh` + `deploy.sh`). Built-in node (label `built-in`) là node fallback.
- Máy local: container `jenkins-local-agent` (label `local-builder`) kết nối **ra** controller qua WebSocket
  (qua `https://jenkins.motcaigido.xyz/`). Build chạy hoàn toàn trong container: `docker build/run` đi tới
  Docker daemon riêng `jenkins-local-agent-docker` (DinD), không dùng `docker.sock` của host.
  Image, cache và workspace nằm trong các volume `jenkins-local-agent-*`. Có thể giới hạn tài nguyên bằng
  `AGENT_CPUS`, `AGENT_MEMORY` trong `agent/.env`.
  Dọn cache build: `sudo docker exec jenkins-local-agent-docker docker system prune -af`.
- Jenkinsfile kiểm tra `local-builder` có online không (`nodesByLabel`) → online thì build ở local, ngược lại build trên dev server.

### 1. Trên dev server
```
bash build.sh && bash deploy.sh
```
Manage Jenkins > System > Jenkins URL: điền `http://<dev-server>:30006/` (bắt buộc cho WebSocket agent).

### 2. Tạo node trong Jenkins
Manage Jenkins > Nodes > New Node:
- Name: `local-builder`, Permanent Agent
- Remote root directory: `/home/jenkins/agent`
- Labels: `local-builder`
- Usage: *Only build jobs with label expressions matching this node*
- Launch method: *Launch agent by connecting it to the controller*, tick **Use WebSocket**
- Availability: *Keep this agent online as much as possible*

Lưu lại, mở node để lấy `secret`.

### 3. Trên máy local
```
cp agent/.env.example agent/.env   # điền JENKINS_URL, JENKINS_SECRET
bash agent/run-agent.sh
```
Container chạy `--restart=always` nên bật lại máy là agent tự online.

### 4. Pipeline
Đặt đoạn sau ở đầu Jenkinsfile của mỗi project (xem `Jenkinsfile`, `Jenkinsfile.template`):
```groovy
env.PRIMARY_BUILD_LABEL = 'local-builder'
env.FALLBACK_BUILD_LABEL = 'built-in'
env.BUILD_LABEL = nodesByLabel(label: env.PRIMARY_BUILD_LABEL, offline: false) ? env.PRIMARY_BUILD_LABEL : env.FALLBACK_BUILD_LABEL

pipeline {
    agent { label "${env.BUILD_LABEL}" }
    ...
}
```
Lưu ý:
- Việc chọn node diễn ra lúc bắt đầu build. Nếu máy local tắt giữa chừng, build đó fail → chạy lại sẽ tự sang dev server.
- Nếu local online nhưng đang bận, build sẽ xếp hàng chờ local (không chuyển sang dev server).
- Plugin cần có: `pipeline-utility-steps` (cho `nodesByLabel`), `ssh-agent` — đã thêm trong `Dockerfile`.

## Docker agent
```
docker run -d --restart=always -p 127.0.0.1:2376:2375 --network jenkins -v /var/run/docker.sock:/var/run/docker.sock alpine/socat tcp-listen:2375,fork,reuseaddr unix-connect:/var/run/docker.sock
```
