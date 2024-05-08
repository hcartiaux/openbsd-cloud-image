#!/usr/bin/env sh

function add_part {
path=$1
size=$2

echo "Adding ${path} (size=$2)"
echo "a\n\n\n${size}\n\n${path}\nw\n"| disklabel -f /etc/fstab -E sd0
mkdir -p ${path}
new_dev=$(cat /etc/fstab |grep " ${path} "|cut -d " " -f 1|sed 's,/dev/,,')
newfs ${new_dev}
if [ -d ${path} ]; then
mv ${path} ${path}.orig
mkdir -p ${path}
mount ${path}
cp -Rp  ${path}.orig/* ${path}
rm -r ${path}.orig
fi
}


add_part /tmp 1000000
add_part /var 400000
add_part /usr 6000000
add_part /usr/X11R6 600000
add_part /usr/local 6000000
add_part /usr/src 600000
add_part /usr/obj 600000
add_part /home    *
