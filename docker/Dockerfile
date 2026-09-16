# syntax=docker/dockerfile:1.7
#
# FLOCS / LOFAR software for Docker Desktop on Apple Silicon (M1 and newer).
# Native linux/arm64 image, translated from Singularity.intel_mkl with the
# MKL, CUDA and x86-only parts (Oracle client, DS9, CASA tarball) removed.
#
# Every component is its own RUN step, so a failure only re-runs that step.
#
# Build:
#   docker build --platform linux/arm64 --progress=plain -t flocs:arm64 .
# Debug a failing step (keeps all intermediate layers, no flattening):
#   docker build --platform linux/arm64 --progress=plain --target build -t flocs:build .
#
# Build context must contain: Dockerfile, dnf-packages.txt,
# build_environment_variables.sh

############################################################################
FROM fedora:42 AS build

# armv8.4-a is the common baseline of all Apple M-series CPUs.
ARG MARCH=armv8.4-a
ARG MTUNE=generic
ARG OPENBLASTARGET=VORTEX
ARG INSTALLDIR=/opt/lofar
# Parallel build jobs. Empty = nproc. Lower this if the Docker VM runs out of memory.
ARG JOBS=

ENV INSTALLDIR=${INSTALLDIR}
WORKDIR ${INSTALLDIR}

COPY dnf-packages.txt build_environment_variables.sh ${INSTALLDIR}/

# Environment shared by all build steps. Each RUN below sources this first,
# because exported variables do not survive from one RUN to the next.
COPY <<'EOF' /opt/lofar/docker-build-env.sh
export HAS_CUDA=false
export HAS_MKL=false
export DEBUG=false
export NOAVX512=false
export INSTALL_CASA=false
export OPENBLAS_TARGET=${OPENBLASTARGET}

source ${INSTALLDIR}/build_environment_variables.sh
if [ -n "${JOBS}" ]; then export J=${JOBS}; fi

# build_environment_variables.sh hardcodes the x86 OpenMPI include dir.
export CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH//openmpi-x86_64/openmpi-$(uname -m)}
export CPATH=${CPATH//openmpi-x86_64/openmpi-$(uname -m)}

export CC=gcc
export CXX=g++
export HDF5_DIR=/opt/hdf5
export FLEXIBLAS=OPENBLAS

# Python: always Fedora's python3.12, never 3.13, never a uv-downloaded one.
export UV_PYTHON_PREFERENCE=only-system
export UV_PYTHON_DOWNLOADS=never
export UV_TOOL_DIR=/opt/uv-tools
export UV_TOOL_BIN_DIR=/usr/local/bin
export SYSPYTHON=/usr/bin/python${PYTHON_VERSION}
# The venv is "active" for every step once it exists (same effect as
# sourcing bin/activate). uv pip then installs into it.
export VIRTUAL_ENV=${INSTALLDIR}/pyenv-py3
export UV_PYTHON=${VIRTUAL_ENV}/bin/python
export PATH=${VIRTUAL_ENV}/bin:/usr/local/bin:${PATH}
if [ -x "${VIRTUAL_ENV}/bin/python" ]; then
    PYEXE=${VIRTUAL_ENV}/bin/python
    export CMAKE_ADD_OPTION="${CMAKE_ADD_OPTION} -DPython3_FIND_VIRTUALENV=ONLY -DPython3_EXECUTABLE=${PYEXE} -DPython_EXECUTABLE=${PYEXE} -DPYTHON_EXECUTABLE=${PYEXE}"
fi

cd ${INSTALLDIR}
set -exo pipefail
EOF

#
# System installs
#
RUN <<'EOF'
#!/bin/bash
set -exo pipefail
dnf -y update
dnf -y install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf -y install wget which
dnf -y install $(<${INSTALLDIR}/dnf-packages.txt)
dnf -y install python3.12 python3.12-devel
python3 -m pip install uv
dnf -y clean all
EOF

#
# OpenBLAS (with bfloat16 kernels: the aarch64 torch wheels need sbgemm_)
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p /opt/OpenBLAS
cd /opt/OpenBLAS
git clone https://github.com/OpenMathLib/OpenBLAS.git src
cd src && git checkout $OPENBLAS_VERSION
mkdir build && cd build
cmake $CMAKE_ADD_OPTION -DCMAKE_INSTALL_PREFIX=/opt/OpenBLAS -DBUILD_TESTING=OFF -DTARGET=$OPENBLAS_TARGET \
    -DBUILD_BFLOAT16=ON \
    -DUSE_THREAD=1 -DNUM_THREADS=$NUM_THREADS -DNUM_CORES=$NUM_THREADS -DBUILD_SHARED_LIBS=ON ..
make -j$J
make install
rm -rf /opt/OpenBLAS/src
# No grep -q: it exits on the first match, nm gets SIGPIPE and pipefail fails the step.
nm -D --defined-only /opt/OpenBLAS/lib64/libopenblas.so | grep sbgemm_
flexiblas add OPENBLAS /opt/OpenBLAS/lib64/libopenblas.so
EOF

#
# HDF5 with parallel support
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
export CC=mpicc
export CXX=mpic++
mkdir /opt/hdf5
cd /opt/hdf5
export HDF5_VERSION_USCORE=${HDF5_VERSION//./_}
wget --progress=bar:force:noscroll https://support.hdfgroup.org/releases/hdf5/v${HDF5_VERSION_USCORE%_*}/v${HDF5_VERSION_USCORE}/downloads/hdf5-${HDF5_VERSION}.tar.gz
tar xzf hdf5-${HDF5_VERSION}.tar.gz
cd hdf5-${HDF5_VERSION}/
# Thread safety required for WSClean's parallel gridding with facets.
./configure -prefix=/opt/hdf5 --enable-build-mode=production --enable-threadsafe --enable-shared --disable-sharedlib-rpath --disable-hl --enable-cxx -enable-unsupported
make -j $J
make install
cd /opt/hdf5
rm -rf hdf5-1.*
EOF

#
# MultiNest
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p MultiNest
git clone https://github.com/JohannesBuchner/MultiNest MultiNest-src
cd MultiNest-src/build
cmake $CMAKE_ADD_OPTION -DCMAKE_INSTALL_PREFIX=$INSTALLDIR/MultiNest ..
make install
cd $INSTALLDIR
rm -rf MultiNest-src
EOF

#
# Python: uv tools and the main venv
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
uv tool install --python $SYSPYTHON breizorro
uv venv --seed --python $SYSPYTHON $INSTALLDIR/pyenv-py3
# Without this the environment doesn't load when sourced from sh.
sed -i "29,41d" $INSTALLDIR/pyenv-py3/bin/activate
$INSTALLDIR/pyenv-py3/bin/python --version | grep "Python ${PYTHON_VERSION}"
EOF

RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
git clone --recurse-submodules https://github.com/tikk3r/flocs.git
EOF

RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
git clone https://github.com/mattyowl/astLib.git
patch astLib/setup.py flocs/patches/astlib.patch
uv pip install --upgrade pip wheel Cython "setuptools>=59.5.0,<71"
CC=$(which gcc-14) uv pip install ./astLib
rm -rf ./astLib
EOF

RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
python -c "import torch; print(torch.__version__)"
uv pip install --no-build-isolation git+https://github.com/sara-nl/cortExchange#egg=cortexchange
EOF

RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
uv pip install scikit_build_core setuptools_scm
uv pip install "numpy<2.5"
uv pip install --no-binary pandas pandas
uv pip install --no-binary h5py h5py
EOF

#
# Boost (built here so Boost.Python/NumPy match the venv)
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
wget https://archives.boost.io/release/1.89.0/source/boost_1_89_0.tar.gz
tar -xzf boost_1_89_0.tar.gz
cd boost_1_89_0
./bootstrap.sh --with-libraries=python --with-python=$VIRTUAL_ENV/bin/python
./b2 -j $J --without-test python=${PYTHON_VERSION} threading=multi \
    cflags="$(python${PYTHON_VERSION}-config --cflags)" \
    cxxflags="$(python${PYTHON_VERSION}-config --includes)" \
    linkflags="$(python${PYTHON_VERSION}-config --libs)" install
cd $INSTALLDIR
rm -rf boost_1_89_0.tar.gz boost_1_89_0
EOF

#
# CASAcore
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p ${INSTALLDIR}/casacore/build ${INSTALLDIR}/casacore/data
cd $INSTALLDIR/casacore
git clone --single-branch --filter=blob:none --branch master https://github.com/casacore/casacore.git src
cd ${INSTALLDIR}/casacore/src && git checkout ${CASACORE_VERSION}
echo export CASACORE_VERSION=$(git rev-parse --short HEAD) >> $INSTALLDIR/init.sh
cd ${INSTALLDIR}/casacore/data
wget -nv https://www.astron.nl/iers/WSRT_Measures.ztar
tar xf WSRT_Measures.ztar && rm WSRT_Measures.ztar
cd ${INSTALLDIR}/casacore/build
cmake $CMAKE_ADD_OPTION \
    -DCMAKE_INSTALL_PREFIX=${INSTALLDIR}/casacore/ \
    -DDATA_DIR=${INSTALLDIR}/casacore/data \
    -DUSE_OPENMP=True \
    -DUSE_HDF5=True \
    -DBUILD_DYSCO=ON \
    -DBUILD_SISCO=ON \
    -DBLAS_LIBRARIES=/opt/OpenBLAS/lib64/libopenblas.so \
    -DBUILD_TESTING=OFF \
    ../src
make -s -j ${J}
make install
cd $INSTALLDIR
rm -rf $INSTALLDIR/casacore/build $INSTALLDIR/casacore/src
EOF

#
# python-casacore, built once against the casacore above and installed into the
# venv. The wheel stays in /opt/wheels so requirements.txt and the uv tools reuse
# this exact version instead of building their own (PyPI has no aarch64 wheels).
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
# dask-ms (shadems, requirements.txt) needs python-casacore >= 3.7.
python -c "import sys; v=tuple(map(int,'${PYTHON_CASACORE_VERSION}'.split('.')[:2])); sys.exit(v < (3, 7))"
mkdir -p /opt/wheels /tmp/sdist
pip download --no-deps --no-binary :all: --dest /tmp/sdist "python-casacore==${PYTHON_CASACORE_VERSION}"
# scikit-build-core passes CMAKE_ARGS on to cmake.
CMAKE_ARGS="-DCASACORE_ROOT_DIR=${INSTALLDIR}/casacore" \
    uv build --wheel --no-config --python $SYSPYTHON --out-dir /opt/wheels /tmp/sdist/python_casacore-${PYTHON_CASACORE_VERSION}.tar.gz
rm -rf /tmp/sdist
echo "python-casacore==${PYTHON_CASACORE_VERSION}" > /opt/wheels/constraints.txt
uv pip install --no-deps --no-index /opt/wheels/python_casacore-${PYTHON_CASACORE_VERSION}-*.whl
python -c "import casacore.tables; print(casacore.__version__)"
EOF

# From here on uv only ever uses the wheel above for python-casacore.
ENV UV_FIND_LINKS=/opt/wheels \
    UV_CONSTRAINT=/opt/wheels/constraints.txt

#
# PyBDSF, before requirements.txt (which pulls it in and installs with
# --no-build-isolation, so bdsf's build backend scikit-build would be missing).
# A normal isolated build fetches its own build tools.
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
uv pip install bdsf
python -c "import bdsf"
EOF

#
# PyQt5 (for lofar-h5plot). PyPI has no linux/aarch64 wheels for PyQt5,
# PyQt5-sip or PyQt5-Qt5, so build PyQt5 and PyQt5-sip against Fedora's Qt5.
# PyQt5-Qt5 (the bundled Qt) is not needed then, and is removed from the
# dependency tree with a uv override. Without all this uv falls back to
# PyQt5 5.15.2, the last release that doesn't require PyQt5-Qt5.
# No version pin: this builds the latest PyQt5, and uv then picks that wheel.
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
dnf -y install qt5-qtbase-devel
dnf -y clean all
# sip 6.16.1 can't build PyQt5 ("ABI v12 is being targeted but the
# PyQt5.QtCore module doesn't support it", Python-SIP/sip#114).
# --build-constraint caps sip in pip's isolated build environment
# (recent pip no longer applies plain -c / PIP_CONSTRAINT there).
pip --version
echo "sip<6.16" > /tmp/build-constraints.txt
pip wheel --no-deps --wheel-dir /opt/wheels --build-constraint /tmp/build-constraints.txt \
    "PyQt5-sip>=12.15,<13"
pip wheel --no-deps --wheel-dir /opt/wheels --build-constraint /tmp/build-constraints.txt \
    --config-settings --confirm-license= \
    --config-settings --qmake=/usr/bin/qmake-qt5 \
    --verbose \
    PyQt5
rm /tmp/build-constraints.txt
echo "PyQt5-Qt5 ; sys_platform == 'never'" > /opt/wheels/overrides.txt
uv pip install --override /opt/wheels/overrides.txt PyQt5
python -c "from PyQt5 import QtCore; print(QtCore.PYQT_VERSION_STR)"
EOF

ENV UV_OVERRIDE=/opt/wheels/overrides.txt

RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
# --no-build-isolation: build backends like scikit-build-core can't fetch ninja themselves.
uv pip install ninja
# everybeam has no aarch64 wheels on PyPI; the Python module comes from our own
# EveryBeam build (on PYTHONPATH via init.sh). Drop it as a pip dependency
# for this and all later installs.
echo "everybeam ; sys_platform == 'never'" >> /opt/wheels/overrides.txt
# lsmtool needs everybeam: installed separately after the EveryBeam step.
grep -v -i -x -E '[[:space:]]*lsmtool[[:space:]]*' $INSTALLDIR/flocs/requirements.txt \
    | xargs -n 1 uv pip install --no-build-isolation
EOF

RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
# Install facetselfcal this way to make sure data gets installed.
git clone https://github.com/rvweeren/lofar_facet_selfcal.git
uv pip install ./lofar_facet_selfcal
uv pip install ./flocs
EOF

#
# LTA client
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
wget --progress=bar:force:noscroll https://lta.lofar.eu/software/lofar_lta-2.8.0.tar.gz
tar xf lofar_lta-2.8.0.tar.gz
uv pip install ./lofar_lta-2.8.0
rm -rf lofar_lta-2.8.0.tar.gz lofar_lta-2.8.0/
EOF

#
# uv tools that need python-casacore. They get the python-casacore wheel from
# /opt/wheels through UV_FIND_LINKS.
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
uv tool install --python $SYSPYTHON shadems --with "pyarrow,dask<2025"
uv tool install --python $SYSPYTHON lofar-vlbi-plot --with "python-casacore"
EOF

#
# SAGECal
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p $INSTALLDIR/sagecal/build
cd $INSTALLDIR/sagecal
git clone https://github.com/nlesc-dirac/sagecal.git src
cd build
cmake $CMAKE_ADD_OPTION -DOpenBLAS_LIB=/opt/OpenBLAS/lib64/libopenblas.so \
    -DCMAKE_INSTALL_PREFIX=$INSTALLDIR/sagecal \
    -DLIB_ONLY=True \
    ../src
make -j $J
make install
rm -rf $INSTALLDIR/sagecal/build $INSTALLDIR/sagecal/src
EOF

#
# AOFlagger
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p ${INSTALLDIR}/aoflagger/build
cd ${INSTALLDIR}/aoflagger
git clone https://gitlab.com/aroffringa/aoflagger.git src
cd src && git checkout ${AOFLAGGER_VERSION}
echo export AOFLAGGER_VERSION=$(git rev-parse --short HEAD) >> $INSTALLDIR/init.sh
cd ${INSTALLDIR}/aoflagger/build
cmake $CMAKE_ADD_OPTION -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=${INSTALLDIR}/aoflagger/ -DCASACORE_ROOT_DIR=${INSTALLDIR}/casacore \
    -DBUILD_SHARED_LIBS=ON -DTARGET_CPU=$MARCH -DPORTABLE=False ../src
make -s -j ${J}
make install
cd $INSTALLDIR
rm -rf $INSTALLDIR/aoflagger/build $INSTALLDIR/aoflagger/src
EOF

#
# LofarStMan
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p $INSTALLDIR/lofarstman
cd $INSTALLDIR/lofarstman
git clone https://github.com/lofar-astron/LofarStMan.git
mkdir LofarStMan/build && cd LofarStMan/build
cmake $CMAKE_ADD_OPTION -DCASACORE_ROOT_DIR=$INSTALLDIR/casacore -DCMAKE_INSTALL_PREFIX=$INSTALLDIR/lofarstman ..
make -j$J
make install
rm -rf $INSTALLDIR/lofarstman/LofarStMan
EOF

#
# EveryBeam
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p $INSTALLDIR/EveryBeam/build
cd $INSTALLDIR/EveryBeam
git clone https://git.astron.nl/RD/EveryBeam.git src
cd src && git checkout $EVERYBEAM_VERSION
echo export EVERYBEAM_VERSION=$(git rev-parse --short HEAD) >> $INSTALLDIR/init.sh
cd $INSTALLDIR/EveryBeam/build
cmake $CMAKE_ADD_OPTION -DCMAKE_INSTALL_PREFIX=$INSTALLDIR/EveryBeam -DBUILD_WITH_PYTHON=ON -DTARGET_CPU=$MARCH ../src
make -j $J
make install
rm -rf $INSTALLDIR/EveryBeam/src $INSTALLDIR/EveryBeam/build
EOF

#
# lsmtool (needs EveryBeam, built above; not taken from PyPI, see overrides.txt)
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
uv pip install lsmtool
EB_PYDIR=$(dirname "$(find $INSTALLDIR/EveryBeam -name 'everybeam*.so' | head -n 1)")
PYTHONPATH=$EB_PYDIR python -c "import everybeam, lsmtool; print(everybeam.__file__, lsmtool.__file__)"
EOF

#
# Image Domain Gridder (IDG)
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p $INSTALLDIR/idg && cd $INSTALLDIR/idg
git clone https://git.astron.nl/RD/idg.git src
cd src && git checkout $IDG_VERSION
echo export IDG_VERSION=$(git rev-parse --short HEAD) >> $INSTALLDIR/init.sh
mkdir build && cd build
cmake $CMAKE_ADD_OPTION -DCMAKE_INSTALL_PREFIX=$INSTALLDIR/idg -DBUILD_WITH_MKL=OFF -DBUILD_LIB_CUDA=OFF -DTARGET_CPU=$MARCH -DCMAKE_BUILD_TYPE=Release ..
make -j $J
make install
rm -rf $INSTALLDIR/idg/src
EOF

#
# DP3
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p $INSTALLDIR/DP3/build
git clone https://git.astron.nl/RD/DP3.git $INSTALLDIR/DP3/src
cd $INSTALLDIR/DP3/src
git checkout ${DP3_VERSION}
echo export DP3_VERSION=$(git rev-parse --short HEAD) >> $INSTALLDIR/init.sh
# The bundled 'predict' checks TARGET_CPU but then compiles with
# -march=native;-mavx2: an x86-only flag, and the build host's CPU (which may
# not run on an M1). Drop -mavx2 and use TARGET_CPU instead of native.
git submodule update --init --recursive
PREDICT_CPU_CMAKE=external/predict/cmake/SetTargetCPU.cmake
sed -i -e 's/;-mavx2//g' -e 's/-march=native/-march=${TARGET_CPU}/g' $PREDICT_CPU_CMAKE
grep -n 'march' $PREDICT_CPU_CMAKE
if grep -q -E -- '-mavx2|-march=native' $PREDICT_CPU_CMAKE; then
    echo "predict still uses -mavx2 or -march=native" >&2; exit 1
fi
# predict also dispatches to xsimd::neon (32-bit ARM, no double-precision
# SIMD). xsimd enables that arch on aarch64 too, which breaks the build
# ("compatible sizes"). Keep only neon64, as newer predict versions do.
PREDICT_ARCHS=external/predict/include/predict/XSimdArchitectures.h
sed -i -e 's/xsimd::neon64,/xsimd::neon64/' -e '/xsimd::neon[[:space:]]*\/\/ ARM32/d' $PREDICT_ARCHS
cat $PREDICT_ARCHS
if grep -q -E 'xsimd::neon([^0-9]|$)' $PREDICT_ARCHS; then
    echo "predict still dispatches to xsimd::neon" >&2; exit 1
fi
# predict includes the x86-only <immintrin.h> without using it; include it on
# x86 only.
grep -rl --include='*.cpp' --include='*.h' '^#include <immintrin.h>' external/predict \
    | xargs -r sed -i 's|^#include <immintrin.h>|#if defined(__x86_64__) \|\| defined(__i386__)\n#include <immintrin.h>\n#endif|'
grep -rn -B1 -A1 --include='*.cpp' --include='*.h' 'immintrin.h' external/predict || true
cd $INSTALLDIR/DP3/build
cmake $CMAKE_ADD_OPTION -DCMAKE_INSTALL_PREFIX:PATH=$INSTALLDIR/DP3 \
    -DIDGAPI_LIBRARIES=$INSTALLDIR/idg/lib/libidg-api.so -DIDGAPI_INCLUDE_DIRS=$INSTALLDIR/idg/include \
    -DAOFLAGGER_INCLUDE_DIR=$INSTALLDIR/aoflagger/include -DAOFLAGGER_LIB=$INSTALLDIR/aoflagger/lib/libaoflagger.so \
    -DTARGET_CPU=${MARCH} -DLIBDIRAC_PREFIX=$INSTALLDIR/sagecal/ -DMETADATA_COMPRESSION_DEFAULT=True \
    -DGIT_SUBMODULE=OFF \
    ../src
make -s -j $J
make install
cd $INSTALLDIR
rm -rf $INSTALLDIR/DP3/build $INSTALLDIR/DP3/src
mkdir $INSTALLDIR/DP3/usermodules
cp $INSTALLDIR/lofar_facet_selfcal/submods/polconv.py $INSTALLDIR/DP3/usermodules/polconv.py
EOF

#
# LoSiTo and LoSoTo
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
uv pip install --no-deps git+https://github.com/darafferty/losito.git
git clone https://github.com/revoltek/losoto.git losoto-src
cd losoto-src && git checkout $LOSOTO_VERSION && cd ..
echo export LOSOTO_VERSION=$LOSOTO_VERSION >> $INSTALLDIR/init.sh
uv pip install --no-deps ./losoto-src
rm -rf losoto-src
EOF

#
# WSClean
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir $INSTALLDIR/wsclean
cd ${INSTALLDIR}/wsclean
git clone https://gitlab.com/aroffringa/wsclean.git
cd wsclean && git checkout $WSCLEAN_VERSION
echo export WSCLEAN_VERSION=$(git rev-parse --short HEAD) >> $INSTALLDIR/init.sh
mkdir build && cd build
export CC=mpicc
export CXX=mpic++
cmake $CMAKE_ADD_OPTION -DCMAKE_INSTALL_PREFIX=$INSTALLDIR/wsclean -DTARGET_CPU=${MARCH} ..
make -j ${J}
make install
rm -rf $INSTALLDIR/wsclean/wsclean
EOF

#
# STILTS
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mkdir -p $INSTALLDIR/stilts
cd $INSTALLDIR/stilts
wget https://www.star.bris.ac.uk/~mbt/stilts/stilts.jar
wget https://www.star.bris.ac.uk/~mbt/stilts/stilts
chmod +x stilts
EOF

#
# DDF dependencies and LOFARBeam (DDFacet still uses it)
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
uv pip --no-cache-dir install meqtrees-cattery --no-deps
uv pip --no-cache-dir install owlcat --no-deps

mkdir -p $INSTALLDIR/LOFARBeam/build
cd $INSTALLDIR/LOFARBeam
git clone https://github.com/lofar-astron/LOFARBeam.git src
cd src
sed -i "s/-std=c++11/-std=${CPPSTD}/" CMakeLists.txt
echo export LOFARBEAM_VERSION=$(git rev-parse --short HEAD) >> $INSTALLDIR/init.sh
cd ../build
mkdir -p $INSTALLDIR/lofar/lib64/python${PYTHON_VERSION}/site-packages/lofar/
touch $INSTALLDIR/lofar/lib64/python${PYTHON_VERSION}/site-packages/lofar/__init__.py
cmake $CMAKE_ADD_OPTION -DCMAKE_INSTALL_PREFIX=$INSTALLDIR/lofar ../src
make -j $J
make install
rm -rf $INSTALLDIR/LOFARBeam
EOF

#
# DDFacet, killMS, DynSpecMS
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
git clone --single-branch -b v1.0.0.0 https://github.com/saopicc/DDFacet.git
sed -i '669s/None:/None and weights is not 1:/' DDFacet/DDFacet/Data/ClassVisServer.py
uv pip install --no-deps DDFacet/

#git clone --single-branch -b v3.3.0 https://github.com/saopicc/killMS.git
#sed -i '558s/$/ parent_affinity=GDPredict["Parallel"]["MainProcessAffinity"],/' killMS/killMS/kMS.py
#for f in SmoothSols.py InterpSols.py Weights/W_Imag.py Weights/W_TimeCov.py Weights/W_ImagCov.py; do
#    sed -i 's/affinity=0/affinity=0, parent_affinity="disable"/' killMS/killMS/$f
#done
#uv pip install --no-deps killMS/

git clone https://github.com/cyriltasse/DynSpecMS.git
cd DynSpecMS && git checkout ApplyBeam
EOF

#
# ddf-pipeline and catalogues
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
git clone https://github.com/mhardcastle/ddf-pipeline.git
cd ddf-pipeline && git checkout $DDFPIPELINE_VERSION && cd ..
sed -i "s/DDF.py/DDF.py --Misc-IgnoreDeprecationMarking=1/" ddf-pipeline/scripts/pipeline.py
sed -i "s/pybdsm\.srl\.fits/pybdsf\.srl\.fits/g" ddf-pipeline/scripts/pipeline.py
sed -i "s/pybdsm\.srl\.fits/pybdsf\.srl\.fits/g" ddf-pipeline/scripts/bootstrap.py
sed -i '353s/readonly=True/readonly=False/' ddf-pipeline/utils/auxcodes.py
sed -i 's/SafeConfigParser/ConfigParser/g' ddf-pipeline/utils/options.py
mkdir DDFCatalogues
cd DDFCatalogues
for c in VLSS wenss B2 NVSS; do
    wget --progress=bar:force:noscroll https://www.extragalactic.info/bootstrap/$c.fits
done
#wget --progress=bar:force:noscroll https://tgssadr.strw.leidenuniv.nl/catalogs/TGSSADR1_7sigma_catalog.fits
EOF

#
# Pipelines and scripts (plain git checkouts)
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
git clone https://github.com/mhardcastle/lotss-query.git
git clone https://github.com/mhardcastle/lotss-hba-survey.git
git clone https://git.astron.nl/RD/LINC.git
git clone https://git.astron.nl/RD/VLBI-cwl.git
EOF

#
# init.sh and cleanup
#
RUN <<'EOF'
#!/bin/bash
source /opt/lofar/docker-build-env.sh
mv flocs/utility .
ln -s $INSTALLDIR/pyenv-py3/bin/h5plot /usr/bin/h5plot
bash $INSTALLDIR/flocs/construct_init.sh
echo . \$INSTALLDIR/pyenv-py3/bin/activate >> $INSTALLDIR/init.sh
rm -rf flocs lofar_facet_selfcal
uv cache clean
dnf -y clean all
rm -rf /var/cache/dnf/* /var/cache/libdnf5/* /var/log/* /root/.cache
EOF

COPY --chmod=0755 <<'EOF' /usr/local/bin/flocs-entrypoint
#!/bin/bash
export INSTALLDIR=/opt/lofar
source $INSTALLDIR/init.sh
exec "$@"
EOF

ENTRYPOINT ["/usr/local/bin/flocs-entrypoint"]
CMD ["bash"]

############################################################################
# Final image: the build stage flattened into one layer, so files deleted in
# later steps (sources, caches) don't take space in the image.
FROM scratch AS final
COPY --from=build / /
ENV INSTALLDIR=/opt/lofar
WORKDIR /opt/lofar
ENTRYPOINT ["/usr/local/bin/flocs-entrypoint"]
CMD ["bash"]
