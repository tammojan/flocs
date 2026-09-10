# FLOCS Docker Image

This image targets `linux/amd64`. It is intended for Docker Desktop on Apple
Silicon, where it runs through Rosetta or QEMU emulation. It is not a macOS
container and cannot execute macOS binaries.

The default image uses OpenBLAS and CPU-only IDG. CUDA, MKL, CASA, Oracle
Instant Client, and DS9 are not enabled by default:

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg HAS_CUDA=false \
  --build-arg HAS_MKL=false \
  --build-arg INSTALL_CASA=false \
  --tag flocs:amd64 \
  --load \
  -f docker/Dockerfile .
```

Run an interactive shell with host data mounted at `/data`:

```bash
docker run --rm -it \
  --platform linux/amd64 \
  --ipc=host \
  --shm-size=16g \
  --ulimit memlock=-1 \
  --volume "$HOME/flocs-data:/data" \
  --volume "$PWD:/workspace" \
  --workdir /workspace \
  flocs:amd64
```

Run a command directly:

```bash
docker run --rm \
  --platform linux/amd64 \
  --volume "$HOME/flocs-data:/data" \
  flocs:amd64 \
  wsclean --version
```

Install DS9 natively on macOS and open files produced in the shared data
directory with:

```bash
open -a "SAOImage DS9" "$HOME/flocs-data/image.fits"
```
