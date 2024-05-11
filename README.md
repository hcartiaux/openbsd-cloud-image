# Qcow2 image builder for OpenBSD

This script generates Qcow2 images of OpenBSD with [cloud-init](https://cloud-init.io/) pre-installed.
The images are ready-to-use for your favorite cloud provider.

## Pre-requisites:

* `python3`
* `sudo`
* `curl`
* `signify` (Debian: `signify-openbsd` and `signify-openbsd-keys`)
* `qemu-system-x86_64`

## Usage

* Clone the git repository
* Run: `./build_openbsd_qcow2.sh -b`
* Done

See `./build_openbsd_qcow2.sh -h` for more information.

## Tips

* Build a standard image: `./build_openbsd_qcow2.sh -r 7.5 --image-file openbsd.qcow2 -b`
* Build a customized image (small disk size, custom disklabel, disabled sets): `./build_openbsd_qcow2.sh -r 7.5 --image-file openbsd-min.qcow2 --size 2 --disklabel custom/disklabel.cloud --sets "-game*.tgz -x*.tgz" --allow_root_ssh no -b`
