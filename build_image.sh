#!/bin/bash
set -e

pwd

# Determine the arch/os we're building for
ARCH=$(uname -m)

# Build cstor
cd ../cstor
make clean
sh autogen.sh
./configure --enable-uzfs=yes --with-config=user --with-jemalloc --with-libcstor=$PWD/../libcstor/include
make clean
make -j$(nproc)

# Build libcstor
cd ../libcstor
make clean
sh autogen.sh
./configure --with-zfs-headers=$PWD/../cstor/include --with-spl-headers=$PWD/../cstor/lib/libspl/include
make -j$(nproc)
sudo make install
sudo ldconfig

# The images can be pushed to any docker/image registeries
# like docker hub, quay. The registries are specified in 
# the `build/push` script.
#
# The images of a project or company can then be grouped
# or hosted under a unique organization key like `openebs`
#
# Each component (container) will be pushed to a unique 
# repository under an organization. 
# Putting all this together, an unique uri for a given 
# image comprises of:
#   <registry url>/<image org>/<image repo>:<image-tag>
#
# IMAGE_ORG can be used to customize the organization 
# under which images should be pushed. 
# By default the organization name is `openebs`. 

if [ -z "${IMAGE_ORG}" ]; then
  IMAGE_ORG="openebs"
fi

# Specify the date of build
DBUILD_DATE=$(date +'%Y-%m-%dT%H:%M:%SZ')

# Specify the docker arg for repository url
if [ -z "${DBUILD_REPO_URL}" ]; then
  DBUILD_REPO_URL="https://github.com/openebs/cstor"
fi

# Specify the docker arg for website url
if [ -z "${DBUILD_SITE_URL}" ]; then
  DBUILD_SITE_URL="https://openebs.io"
fi

DBUILD_ARGS="--build-arg DBUILD_DATE=${DBUILD_DATE} --build-arg DBUILD_REPO_URL=${DBUILD_REPO_URL} --build-arg DBUILD_SITE_URL=${DBUILD_SITE_URL} --build-arg ARCH=${ARCH}"


if [ "${ARCH}" = "x86_64" ]; then
	REPO_NAME="$IMAGE_ORG/cstor-base"
	DOCKERFILE_BASE="Dockerfile.base"
	DOCKERFILE="Dockerfile"
elif [ "${ARCH}" = "aarch64" ]; then
	REPO_NAME="$IMAGE_ORG/cstor-base-arm64"
	DOCKERFILE_BASE="Dockerfile.base.arm64"
	DOCKERFILE="Dockerfile.arm64"
else
	echo "${ARCH} is not supported"
	exit 1
fi

mkdir -p ./docker/zfs/bin
mkdir -p ./docker/zfs/lib

cp cmd/zrepl/.libs/zrepl ./docker/zfs/bin
cp ../cstor/cmd/zpool/.libs/zpool ./docker/zfs/bin
cp ../cstor/cmd/zfs/.libs/zfs ./docker/zfs/bin
cp ../cstor/cmd/zstreamdump/.libs/zstreamdump ./docker/zfs/bin

cp ../cstor/lib/libzpool/.libs/*.so* ./docker/zfs/lib
cp ../cstor/lib/libuutil/.libs/*.so* ./docker/zfs/lib
cp ../cstor/lib/libnvpair/.libs/*.so* ./docker/zfs/lib
cp ../cstor/lib/libzfs/.libs/*.so* ./docker/zfs/lib
cp ../cstor/lib/libzfs_core/.libs/*.so* ./docker/zfs/lib
cp src/.libs/*.so* ./docker/zfs/lib

sudo docker version
sudo docker build --help

curl --fail https://raw.githubusercontent.com/openebs/charts/gh-pages/scripts/release/buildscripts/push > ./docker/push
chmod +x ./docker/push

## Building image for cstor-base
echo "Build image ${REPO_NAME}:ci with BUILD_DATE=${DBUILD_DATE}"
cd docker && \
 sudo docker build -f ${DOCKERFILE_BASE} -t ${REPO_NAME}:ci ${DBUILD_ARGS} . && \
 DIMAGE=${REPO_NAME} ./push && \
 cd ..
if [ $? -ne 0 ]; then
 echo "Failed to run push script for ${REPO_NAME}"
 exit 1
fi

if [ "${ARCH}" = "x86_64" ]; then
	REPO_NAME="$IMAGE_ORG/cstor-pool"
elif [ "${ARCH}" = "aarch64" ]; then
	REPO_NAME="$IMAGE_ORG/cstor-pool-arm64"
fi 

echo "Build image ${REPO_NAME}:ci with BUILD_DATE=${DBUILD_DATE}"
cd docker && \
 sudo docker build -f ${DOCKERFILE} -t ${REPO_NAME}:ci ${DBUILD_ARGS} . && \
 DIMAGE=${REPO_NAME} ./push && \
 cd ..
if [ $? -ne 0 ]; then
 echo "Failed to run push script for ${REPO_NAME}"
 exit 1
fi

rm -rf ./docker/zfs