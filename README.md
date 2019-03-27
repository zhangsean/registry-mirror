# registry-mirror
基于官方[registry](https://hub.docker.com/_/registry/)的便捷docker仓库镜像，非常方便在内网搭建镜像缓存服务，在一定网络下还可以实现墙外docker仓库的镜像.

[![DockerHub Badge](http://dockeri.co/image/zhangsean/registry-mirror)](https://hub.docker.com/r/zhangsean/registry-mirror/)

## 用法
### 内网镜像仓库缓存
在内网`node1`主机上启动一个仓库镜像服务指向阿里云镜像加速服务，首次拉取某个版本的镜像`node1`不存在则自动向阿里云拉取并缓存到本地，下次拉取这个镜像时将直接从`node1`的缓存中返回，大大提升内网拉取镜像的速度。也可用于跨区域的机房之间的镜像按需自动同步缓存。
```
docker run -itd -p 80:5000 -e PROXY_REMOTE_URL=https://xxxxxxxx.mirror.aliyuncs.com --name reg-aliyun zhangsean/registry-mirror
```
在内网其他主机上设置`node1`为受信任的仓库镜像，
```
vi /etc/docker/daemon.json
{
    "insecure-registries": ["node1"],
    "registry-mirrors": ["http://node1"]
}
systemctl restart docker
```
之后内网主机拉取镜像只需要写镜像名，不需要指定镜像仓库
```
docker pull nginx
```
内网其他主机拉取相同镜像速度将会被加速
```
docker pull nginx
```

### 墙外镜像仓库代理
在一个 **不被墙** 的服务器`hk`上以`5001`端口启动一个指向`gcr.io`的镜像代理:
```
docker run -itd -p 5001:5000 -v /data/registry:/var/lib/registry -e PROXY_REMOTE_URL=https://gcr.io --name reg-gcr zhangsean/registry-mirror
```
墙内主机可以通过`hk`拉取墙外镜像
```
docker pull hk:5001/istio-release/servicegraph:release-1.0-latest-daily
# 实现了拉取
docker pull gcr.io/istio-release/servicegraph:release-1.0-latest-daily
```

同理以`5002`端口启动一个指向`quay.io`的镜像代理：
```
docker run -itd -p 5002:5000 -v /data/registry:/var/lib/registry -e PROXY_REMOTE_URL=https://quay.io --name reg-quay zhangsean/registry-mirror
```
由于很多服务的yaml文件中都指定了镜像仓库比如`gcr.io/k8s/kube-system`，为了方便墙内主机在不修改yaml文件image地址的情况下也可以部署服务，我们可以在墙外主机上启动一个Web服务器把`gcr.io:80`转发到`5001`端口上，以nginx为例
```
tee > nginx-proxy.conf << EOF
server {
    listen       80;
    server_name  gcr.io;
    location / {
        proxy_pass   http://172.17.0.1:5001;
    }
}
server {
    listen       80;
    server_name  quay.io;
    location / {
        proxy_pass   http://172.17.0.1:5002;
    }
}
server {
    listen       80;
    server_name  _ hub.hk.com;
    location / {
        proxy_pass   http://172.17.0.1:5080;
    }
}
EOF
docker run -itd -p 80:80 -v $PWD/nginx-proxy.conf:/etc/nginx/conf.d/default.conf --name nginx nginx:alpine
```

### 一键部署镜像仓库代理
您也可以通过`docker-compose`快速启动一组实现`gcr.io`、`k8s.gcr.io`、`quay.io`几个特殊镜像仓库的代理服务。
```shell
git clone https://github.com/zhangsean/registry-mirror.git
cd registry-mirror/samples/external-mirror
docker-compose up -d
```

### 使用镜像仓库代理
内网的服务器只需要在`hosts`文件或者内网DNS中将`gcr.io`、`k8s.gcr.io`、`quay.io`指向墙外的`hk`服务器IP，同时将这几个域名加入受信任仓库中即可直接拉取墙外镜像。
请替换如下示例中`11.11.1.1`为`hk`服务器IP。
```
echo "11.11.1.1  gcr.io k8s.gcr.io quay.io" >> /etc/hosts
vi /etc/docker/daemon.json
{
    "insecure-registries": ["gcr.io", "k8s.gcr.io", "quay.io"]
}
systemctl daemon-reload
systemctl restart docker
```
现在拉取官方镜像就不用担心被墙了 O(∩ _ ∩)O~
```
docker pull k8s.gcr.io/pause:3.1
docker pull gcr.io/istio-release/servicegraph:release-1.0-latest-daily
```

### 查看缓存的镜像
要想查看缓存的镜像，启动仓库镜像的时候必须把`/var/lib/registry`目录挂载到主机上，然后挂载相同目录启动一个本地镜像服务即可查看缓存的镜像。建议开启删除镜像的功能，可以调用接口删除不需要的镜像：
```
docker run -itd -p 5000:5000 -v /data/registry:/var/lib/registry -e DELETE_ENABLED=true --name reg-local zhangsean/registry-mirror
```
启动`registry-ui`并开启统计镜像大小的功能。
```
docker run -itd -p 5080:80 --link reg-local:registry -e REGISTRY_API=http://registry:5000/v2 -e REGISTRY_WEB=hub.local.com -e SHOW_IMAGE_SIZE=true zhangsean/registry-ui
```
访问 http://server-ip:5080/ 即可查看已经缓存到本地的镜像，非常清楚地看到每个镜像的大小.

### 手工推送本地镜像到本地仓库
编辑 `push.sh`
```
#!/bin/sh
HUB=hub.io
IMG=$1
echo $IMG
IMG=`echo $IMG | sed 's|k8s.gcr.io/||g'`
IMG=`echo $IMG | sed 's|gcr.io/||g'`
IMG=`echo $IMG | sed 's|quay.io/||g'`
echo $HUB/$IMG
docker tag $1 $HUB/$IMG
docker push $HUB/$IMG
docker rmi $HUB/$IMG
```
一行命令即可将本地所有镜像推送到本地仓库中，供其他主机下载。
```
$ chmod +x push.sh
$ for tag in $(docker images | grep -v TAG | awk '{print $1":"$2}'); do ./push.sh $tag; done;
```
