#!/usr/bin/env -S bash --posix
################################################################################
# Description : see the print_help function or launch 'build_openbsd_qcow2 --help'
#
# Based on Stefan Kreutz and Gonéri Le Bouder works:
# * https://www.skreutz.com/posts/autoinstall-openbsd-on-qemu/
# * https://git.skreutz.com/autoinstall-openbsd-on-qemu.git/tree
# * https://github.com/goneri/pcib/blob/master/plugins/package/cloud-init/tasks/77-cloud-init.sh
#
# Copyright (c) 2023 Hyacinthe Cartiaux <hyacinthe.cartiaux@gmail.com>
# Copyright (c) 2020 Stefan Kreutz <mail@skreutz.com>
#
# Permission to use, copy, modify, and distribute this software for any purpose
# with or without fee is hereby granted, provided that the above copyright
# notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.#
#
################################################################################
#set -x

# Defaults
TOP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATH_MIRROR="${TOP_DIR}/mirror"
PATH_IMAGES="${TOP_DIR}/images"
PATH_TFTP="${TOP_DIR}/tftp"

OPENBSD_VERSION="7.5"
OPENBSD_ARCH=amd64

OPENBSD_TRUSTED_MIRROR="https://ftp.openbsd.org/pub/OpenBSD/${OPENBSD_VERSION}"
OPENBSD_MIRROR="https://cdn.openbsd.org/pub/OpenBSD/${OPENBSD_VERSION}"

IMAGE_SIZE=40
IMAGE_NAME="${PATH_IMAGES}/openbsd${v}_$(date +%Y-%m-%d).qcow2"

QEMU_CPUS=1
QEMU_MEM=384m

DISKLABEL="custom/disklabel"
INSTALLCONF="custom/install.conf"

SSH_KEY_VAL=none
HTTP_SERVER=10.0.2.2
HOST_NAME="openbsd"

### Functions

function warning    { echo "[WARNING] $1"; }
function fail       { echo "[FAIL] $*" 1>&2 && exit 1; }
function report     { echo "[INFO] $*"; }
function exec_cmd   {
    if [ "$DRY_RUN" == "DEBUG" ] ; then
        if [[ $1 == "bg" ]]; then
            shift
            echo "[DRY-RUN] $* &"
        else
            echo "[DRY-RUN] $*"
        fi
    else
        echo "[CMD] $*"
        if [[ $1 == "bg" ]]; then
            shift
            $* &
        else
            $*
        fi
        return $?
    fi
}

function check_program {
    program="$1"
    exec_cmd command -v "${program}" || \
        fail "You need ${program} installed and in the path"
}

function check_for_programs {
    check_program sudo
    if grep -E 'Debian|Ubuntu' /etc/os-release 2>&1 > /dev/null ; then
	SIGNIFY_CMD=signify-openbsd
    else
	SIGNIFY_CMD=signify
    fi
    check_program $SIGNIFY_CMD
    check_program qemu-img
    check_program qemu-system-x86_64
    check_program python3
    check_program curl
}

function build_mirror {
    files="base${v}.tgz bsd bsd.mp bsd.rd comp${v}.tgz game${v}.tgz man${v}.tgz pxeboot xbase${v}.tgz xfont${v}.tgz xserv${v}.tgz xshare${v}.tgz"

    exec_cmd curl -C - -O --create-dirs --output-dir "${PATH_MIRROR}/pub/OpenBSD/${OPENBSD_VERSION}" "${OPENBSD_TRUSTED_MIRROR}/openbsd-${v}-base.pub"

    for i in $files SHA256.sig
    do
        exec_cmd curl -C - -O --create-dirs --output-dir "${PATH_MIRROR}/pub/OpenBSD/${OPENBSD_VERSION}/${OPENBSD_ARCH}" "${OPENBSD_MIRROR}/${OPENBSD_ARCH}/$i"
    done

    exec_cmd cd "${TOP_DIR}/custom"
    exec_cmd tar -czf "${PATH_MIRROR}/pub/OpenBSD/${OPENBSD_VERSION}/amd64/site${v}.tgz" install.site

    exec_cmd cd "${PATH_MIRROR}/pub/OpenBSD/${OPENBSD_VERSION}/${OPENBSD_ARCH}"
    exec_cmd ls -l | tail -n +2 | exec_cmd tee index.txt
    exec_cmd $SIGNIFY_CMD -C -p "../openbsd-${v}-base.pub" -x SHA256.sig -- $files
    [[ "$?" != 0 ]] && fail "Signature verifications failed"

    exec_cmd cd "${TOP_DIR}"
    exec_cmd cp -f "${INSTALLCONF}" "${PATH_MIRROR}/install.conf"
    exec_cmd sed -i "s!site[0-9]*.tgz!site${v}.tgz!"                            "${PATH_MIRROR}/install.conf"
    exec_cmd sed -i "s!\(disklabel.=.\).*\$!\1http://${HTTP_SERVER}/disklabel!" "${PATH_MIRROR}/install.conf"
    exec_cmd sed -i "s!\(hostname.=.\).*\$!\1${HOST_NAME}!"                     "${PATH_MIRROR}/install.conf"
    exec_cmd sed -i "s!\(HTTP.Server.=.\).*\$!\1${HTTP_SERVER}!"                "${PATH_MIRROR}/install.conf"
    [[ ! -z "$SSH_KEY" ]] && SSH_KEY_VAL=$(cat $SSH_KEY)
    exec_cmd echo "Set name(s) = ${SETS}"                            | tail -n 1 | exec_cmd tee -a "${PATH_MIRROR}/install.conf"
    exec_cmd echo "Public ssh key for root account = ${SSH_KEY_VAL}" | tail -n 1 | exec_cmd tee -a "${PATH_MIRROR}/install.conf"

    exec_cmd ln -sf "../${DISKLABEL}" "${PATH_MIRROR}/disklabel"
}

function start_mirror {
    exec_cmd bg sudo python3 -m http.server --directory mirror --bind 127.0.0.1 80
    trap "report [7/7] Stop the HTTP mirror server ; exec_cmd kill $(jobs -p)" EXIT
    report Waiting for the HTTP mirror server to be available
    try=0
    while [ ! "$(exec_cmd curl --silent 'http://127.0.0.1/install.conf')" ]
    do
        exec_cmd sleep 1
        try=$((try + 1))
        [[ "$try" -gt 10 ]] && fail "Could not start the HTTP mirror server"
    done
    report HTTP mirror server reachable
}

function build_tftp {
    exec_cmd cd "${TOP_DIR}"
    exec_cmd mkdir -p "${PATH_TFTP}/etc"
    exec_cmd ln -sf "../mirror/pub/OpenBSD/${OPENBSD_VERSION}/amd64/pxeboot" tftp/auto_install
    exec_cmd ln -sf "../mirror/pub/OpenBSD/${OPENBSD_VERSION}/amd64/bsd.rd" tftp/bsd.rd
    exec_cmd ln -sf ../../custom/boot.conf tftp/etc/
}

function create_image {
    exec_cmd mkdir -p "${PATH_IMAGES}"
    exec_cmd qemu-img create -f qcow2 "${IMAGE_NAME}" "${IMAGE_SIZE}G"
    [[ "$?" != 0 ]] && fail "Error while creating the image file ${IMAGE_NAME}"
}

function qemu_enable_kvm {
    if exec_cmd grep -E 'vmx|svm' /proc/cpuinfo 2>&1 > /dev/null ; then
        [[ -w /dev/kvm ]] && echo -n "-enable-kvm"
    fi
}

function launch_install {
    # Skip lines to preserve the output
    exec_cmd seq $(( $(tput lines) + 2  )) | exec_cmd tr -dc '\n'
    # Start qemu
    exec_cmd qemu-system-x86_64 $(qemu_enable_kvm) -nographic -action reboot=shutdown -boot once=n                 \
                                -smp cpus=$QEMU_CPUS -m $QEMU_MEM -drive file="${IMAGE_NAME}",media=disk,if=virtio \
                                -device virtio-net-pci,netdev=n1                                                   \
                                -netdev user,id=n1,hostname=openbsd-vm,tftp=tftp,bootfile=auto_install
    [[ "$?" != 0 ]] && fail "Qemu returned an error"
    exec_cmd qemu-img convert -O qcow2 -c ${IMAGE_NAME} ${IMAGE_NAME}_compressed
    [[ "$?" != 0 ]] && fail "Qemu-img returned an error"
    exec_cmd mv -f ${IMAGE_NAME}_compressed ${IMAGE_NAME}
}

####
# print help
##
print_help() {
    less <<EOF
NAME
  $COMMAND

SYNOPSIS
  $COMMAND [-h|--help]


DESCRIPTION
  $COMMAND build a cloud image of OpenBSD

OPTIONS
  -h --help
    Display a help screen and quit.

  -n --dry-run
    No-op mode

  -b
    Build !

  --image-file FILE_NAME
    File name of the image file, created in ./images (default: $(basename $IMAGE_NAME)

  -s --size SIZE
    QCow2 disk size in GB (default: ${IMAGE_SIZE})

  --disklabel FILE
    Path of your own disklabel file

  --installconf FILE
    Path of your own install.conf file (served via http on the IP address of the next-server provided by qemu/DHCP)

    -r --release OPENBSD_VERSION
      Specify the release (default: ${OPENBSD_VERSION})

    --host_name HOST_NAME
      Hostname of the VM (default: ${HOST_NAME})

    --http_server IP
      IP of the HTTP mirror hosting the sets and disklabel file (default: ${HTTP_SERVER})

    --sshkey <PUB KEY FILE PATH>
      Path to a SSH public key file for the root user (default: ${SSH_KEY_VAL})

    --sets "<SET NAMES>"
      Specify the sets to be installed (default: ${SETS})

AUTHOR
  Hyacinthe Cartiaux <Hyacinthe.Cartiaux@gmail.com>

COPYRIGHT
  This is free software; see the source for copying conditions.
EOF
}


### Let's go

# Check for options
while [ $# -ge 1 ]; do
    case $1 in
        -h | --help)     print_help; exit 0                  ;;
        -n | --dry-run)  DRY_RUN="DEBUG";                    ;;
        -b | --build)    RUN=1;                              ;;
        --image-file)    shift; IMAGE_NAME=${PATH_IMAGES}/$1 ;;
        -s | --size)     shift; IMAGE_SIZE=$1                ;;
        --disklabel)     shift; DISKLABEL=$1                 ;;
        --installconf)   shift; INSTALLCONF=$1               ;;
        --sshkey)        shift; SSH_KEY=$1                   ;;
        -r | --release)  shift; OPENBSD_VERSION=$1           ;;
        --host_name)     shift; HOST_NAME=$1                 ;;
        --http_server)   shift; HTTP_SERVER=$1               ;;
        --sets)          shift; SETS="$1"                    ;;
    esac
    shift
done

[[ ! "${IMAGE_SIZE}"      =~ ^[0-9]+$                                      ]] && fail "Invalid image size"
[[ ! "${OPENBSD_VERSION}" =~ ^[0-9]+\.[0-9+]$                              ]] && fail "Invalid OpenBSD version"
[[ ! "${HOST_NAME}"       =~ ^[a-z0-9-]+$                                  ]] && fail "Invalid hostname"
[[ ! "${HTTP_SERVER}"     =~ ^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$ ]] && fail "${HTTP_SERVER} is not an IPv4"
[[ ! -e "${DISKLABEL}"                                                     ]] && fail "Non existing disklabel file"
[[ ! -e "${INSTALLCONF}"                                                   ]] && fail "Non existing install.conf file"
[[ ! -z "${SSH_KEY}" && ! -e "${SSH_KEY}"                                  ]] && fail "Non existing SSH public key file"

if [[ -z "$RUN" ]]; then
    print_help
    exit 0
else
    v=${OPENBSD_VERSION//./}
    SETS="${SETS} site${v}.tgz"

    report "[1/7] Check for dependencies"
    check_for_programs
    report "[2/7] Build the HTTP mirror server directory"
    build_mirror
    report "[3/7] Build the TFTP server directory for PXE boot"
    build_tftp
    report "[4/7] Start the HTTP mirror server"
    start_mirror
    report "[5/7] Create the QCow2 image file"
    create_image
    report "[6/7] Boot the installer"
    launch_install
    report "QCow2 image generated: ${IMAGE_NAME}"
fi

