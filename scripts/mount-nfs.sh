#!/bin/sh
# NFS mounting script for benchmark containers
# Usage: mount-nfs.sh <nfs_server> <remote_path> <local_mount> <nfs_version> [mount_options]

set -e

NFS_SERVER="$1"
REMOTE_PATH="$2"
LOCAL_MOUNT="$3"
NFS_VERSION="${4:-v4}"
MOUNT_OPTIONS="${5:-rw,hard,rsize=8192,wsize=8192,timeo=14}"

if [ -z "$NFS_SERVER" ] || [ -z "$REMOTE_PATH" ] || [ -z "$LOCAL_MOUNT" ]; then
    echo "Usage: $0 <nfs_server> <remote_path> <local_mount> [nfs_version] [mount_options]"
    exit 1
fi

echo "Mounting NFS: ${NFS_SERVER}:${REMOTE_PATH} -> ${LOCAL_MOUNT} (${NFS_VERSION})"

# Wait for NFS server to be available
echo "Waiting for NFS server to be ready..."
for i in $(seq 1 30); do
    if showmount -e "$NFS_SERVER" >/dev/null 2>&1; then
        echo "NFS server is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Timeout waiting for NFS server"
        exit 1
    fi
    sleep 2
done

# Create mount point
mkdir -p "$LOCAL_MOUNT"

# Unmount if already mounted
if mountpoint -q "$LOCAL_MOUNT"; then
    echo "Unmounting existing mount at $LOCAL_MOUNT"
    umount "$LOCAL_MOUNT" || true
fi

# Mount with specified version and options
case "$NFS_VERSION" in
    "v3")
        MOUNT_CMD="mount -t nfs -o nfsvers=3,nolock,${MOUNT_OPTIONS} ${NFS_SERVER}:${REMOTE_PATH} ${LOCAL_MOUNT}"
        ;;
    "v4")
        MOUNT_CMD="mount -t nfs -o nfsvers=4,${MOUNT_OPTIONS} ${NFS_SERVER}:${REMOTE_PATH} ${LOCAL_MOUNT}"
        ;;
    *)
        echo "Unsupported NFS version: $NFS_VERSION"
        exit 1
        ;;
esac

echo "Executing: $MOUNT_CMD"
eval "$MOUNT_CMD"

# Verify mount
if ! mountpoint -q "$LOCAL_MOUNT"; then
    echo "Mount failed: $LOCAL_MOUNT is not a mountpoint"
    exit 1
fi

echo "Successfully mounted ${NFS_SERVER}:${REMOTE_PATH} at ${LOCAL_MOUNT}"
