# syntax=docker/dockerfile:1
#
# Linux amd64 FLOCS image for Docker Desktop on Apple Silicon.
# The image remains Linux; it is not a macOS container.

FROM fedora:42

ARG HAS_CUDA=false
ARG HAS_MKL=false
ARG MARCH=x86-64
ARG MTUNE=generic
ARG NOAVX512=true
ARG DEBUG=false
ARG INSTALL_CASA=false
ARG INSTALLDIR=/opt/lofar
ARG OPENBLASTARGET=CORE2

ENV INSTALLDIR=${INSTALLDIR}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY dnf-packages.txt /tmp/dnf-packages.txt
COPY build_environment_variables.sh /tmp/build_environment_variables.sh
COPY singularity/Singularity.intel_mkl /tmp/Singularity.intel_mkl

# The existing Apptainer post section is retained as the source of truth. The
# transformations below remove Apptainer-only syntax and Linux desktop/client
# artifacts that cannot be used by Docker Desktop on macOS.
RUN set -euxo pipefail; \
    mkdir -p "${INSTALLDIR}"; \
    cp /tmp/dnf-packages.txt "${INSTALLDIR}/dnf-packages.txt"; \
    cp /tmp/build_environment_variables.sh "${INSTALLDIR}/build_environment_variables.sh"; \
    sed -n '/^%post$/,/^%help$/p' /tmp/Singularity.intel_mkl \
        | sed '1d;$d' \
        | sed \
            -e "s|{{ HAS_CUDA }}|${HAS_CUDA}|g" \
            -e "s|{{ HAS_MKL }}|${HAS_MKL}|g" \
            -e "s|{{ MARCH }}|${MARCH}|g" \
            -e "s|{{ MTUNE }}|${MTUNE}|g" \
            -e "s|{{ NOAVX512 }}|${NOAVX512}|g" \
            -e "s|{{ DEBUG }}|${DEBUG}|g" \
            -e "s|{{ INSTALL_CASA }}|${INSTALL_CASA}|g" \
            -e "s|{{ INSTALLDIR }}|${INSTALLDIR}|g" \
            -e "s|{{ OPENBLASTARGET }}|${OPENBLASTARGET}|g" \
        > /tmp/flocs-post.sh; \
    sed -i \
        '/wget https:\/\/raw.githubusercontent.com\/tikk3r\/flocs\/fedora-py3\/dnf-packages.txt/d' \
        /tmp/flocs-post.sh; \
    sed -i \
        '/wget https:\/\/raw.githubusercontent.com\/tikk3r\/flocs\/fedora-py3\/build_environment_variables.sh/d' \
        /tmp/flocs-post.sh; \
    sed -i \
        '/oracle-instantclient-basic-23.6.0.24.10-1.el9.x86_64.rpm/,+2d' \
        /tmp/flocs-post.sh; \
    sed -i \
        '/^    # Install DS9$/,/^    # Install STILTS$/ { /^    # Install STILTS$/!d; }' \
        /tmp/flocs-post.sh; \
    sed -i \
        's/sudo dnf -y install python3-cx-oracle python3.12 python3.12-devel/dnf -y install python3.12 python3.12-devel/' \
        /tmp/flocs-post.sh; \
    sed -i 's/sudo //g' /tmp/flocs-post.sh; \
    bash /tmp/flocs-post.sh; \
    rm -f /tmp/flocs-post.sh /tmp/Singularity.intel_mkl /tmp/dnf-packages.txt /tmp/build_environment_variables.sh; \
    rm -rf /var/cache/dnf /var/cache/libdnf5 /var/log/*

COPY docker/entrypoint.sh /usr/local/bin/flocs-entrypoint
RUN chmod 0755 /usr/local/bin/flocs-entrypoint

ENTRYPOINT ["/usr/local/bin/flocs-entrypoint"]
CMD ["bash"]
