#!/usr/bin/env bash

sudo apt autoremove 
sudo apt install -y python3-venv python3-pip 

Python_venv=$HOME/SinglePassCapture/PerfInspector/Python-venv
sudo mv -f -t /tmp $Python_venv  
python3 -m venv $Python_venv

$Python_venv/bin/python -m pip install -r $HOME/SinglePassCapture/Scripts/requirements.txt || true
$Python_venv/bin/python -m pip install -r $HOME/SinglePassCapture/PerfInspector/processing/requirements.txt || true 
$Python_venv/bin/python -m pip install -r $HOME/SinglePassCapture/PerfInspector/processing/requirements_0.txt || true 
$Python_venv/bin/python -m pip install -r $HOME/SinglePassCapture/PerfInspector/processing/requirements_perfsim.txt || true 
$Python_venv/bin/python -m pip install -r $HOME/SinglePassCapture/PerfInspector/processing/requirements_with_extra_index.txt || true 
$Python_venv/bin/python -m pip install \
    --index-url https://sc-hw-artf.nvidia.com/artifactory/api/pypi/hwinf-pi-pypi/simple \
    --extra-index-url https://pypi.perflab.nvidia.com/ \
    --extra-index-url https://urm.nvidia.com/artifactory/api/pypi/nv-shared-pypi/simple \
    marisa-trie python-rapidjson memory-profiler py7zr ruyi_formula_calculator \
    idea2txv==0.21.17 perfins==0.5.47 gtl-api==2.25.5 hair-cli \
    pi-uploader wget apm xgboost ruyi-formula-calculator \
    perfins PIFlod lttb idea2txv Pillow psutil==5.9.3 \
    pyyaml joblib xlsxwriter seaborn scikit-learn \
    numexpr openpyxl keyring==23.4.0 requests==2.27.1 \
    requests-toolbelt==0.9.1 tqdm==4.62.3 aem ipdb==0.13.0 \
    dask[complete] prettytable || true

if ! grep -Rhs --include='*.conf' -v '^[[:space:]]*#' /etc/modprobe.d /etc/modprob.d | grep -q 'NVreg_RestrictProfilingToAdminUsers=0' || ! grep -Rhs --include='*.conf' -v '^[[:space:]]*#' /etc/modprobe.d /etc/modprob.d | grep -Eq '(^|[;[:space:]])RmProfilerFeature=0x1([;[:space:]]|"|$)'; then
    echo "Missing one or both settings: NVreg_RestrictProfilingToAdminUsers=0 and RmProfilerFeature=0x1"
fi