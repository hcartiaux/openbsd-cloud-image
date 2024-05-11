#!/usr/bin/env sh

# Script installed by install.site during the qcow2 image generation
# cf. https://github.com/hcartiaux/openbsd-cloud-image/

DISK=$(df / | tail -n1 | sed 's,/dev/\([^ ]*\)a.*,\1,')

function stop_services {
    /etc/rc.d/sndiod stop
    /etc/rc.d/ntpd stop
    /etc/rc.d/smtpd stop
    /etc/rc.d/cron stop
}

function start_services {
    /etc/rc.d/sndiod start
    /etc/rc.d/ntpd start
    /etc/rc.d/smtpd start
    /etc/rc.d/cron start
}

function add_swap {
    size=$1

    echo "Adding swap (size=${size})"
    echo "b\n\n*\na\n\n\n${size}\n\n\nw\n"| disklabel -v -f /etc/fstab -E "${DISK}"
}

function add_part {
    path=$1
    size=$2

    echo "Adding ${path} (size=${size})"
    echo "b\n\n*\na\n\n\n${size}\n\n${path}\nw\n"| disklabel -v -f /etc/fstab -E "${DISK}"
    mkdir -p ${path}
    new_dev=$(grep " ${path} " /etc/fstab|cut -d " " -f 1|sed 's,/dev/,,')
    newfs ${new_dev}

    if [ -d ${path} ]; then
        mv ${path} ${path}.orig
        mkdir -p ${path}
        mount ${path}
        cp -Rp  ${path}.orig/* ${path}
        rm -r ${path}.orig
    fi
}

stop_services
add_swap 400m
add_part /tmp 1000m
add_part /var 4000m
add_part /usr 5000m
add_part /usr/local 6000m
add_part /usr/src 2000m
add_part /usr/obj 2000m
add_part /home    '*'
start_services

