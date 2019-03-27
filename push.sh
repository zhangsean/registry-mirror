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
