#!/bin/bash
####################################################################################################
# @file install-tools.sh
#
# Perform installation or removal of user space applications and drivers.
#
# @author ayegorov@
# @author owner is alexg@
#
# Copyright (c) 2005-2008 Parallels Software International, Inc.
# All rights reserved.
# http://www.parallels.com
####################################################################################################

export LANG=C
PATH=${PATH:+$PATH:}/sbin:/bin:/usr/sbin:/usr/bin:/usr/X11R6/bin

BASE_DIR="$(dirname "$0")"
PMANAGER="$BASE_DIR/pm.sh"
DETECT_X_SERVER="$BASE_DIR/detect-xserver.sh"
CONFIGURE_X_SERVER="$BASE_DIR/xserver-config.py"
REGISTER_SERVICE="$BASE_DIR/install-service.sh"
PRLFS_SELINUX="$BASE_DIR/prlfs.te"
PRLVTG_SELINUX="$BASE_DIR/prlvtg.te"
PRLTOOLSD_SELINUX="$BASE_DIR/prltoolsd.te"
PRL_TOOLS_INITRAMFS_HOOK="$BASE_DIR/parallels_tools.initramfs-hook"

TOOL_DIR="$2"
PT_LIB_DIR="$TOOL_DIR/../lib"
TOOLS_DIR=""
COMMON_TOOLS_DIR=""

BACKUP_DIR="$3"
XCONF_BACKUP="$BACKUP_DIR/.xconf.info"
TOOLS_BACKUP="$BACKUP_DIR/.tools.list"
PSF_BACKUP="$BACKUP_DIR/.psf"
SLP_BACKUP="$BACKUP_DIR/.${SLP_NAME}.selinux"
CTLCENTER_LAUNCHER="prlcc.desktop"
WMOUSED_LAUNCHER="prl_wmouse_d.desktop"
PTIAGENT_LAUNCHER="ptiagent.desktop"
TOOLS_ICON="parallels-tools.png"
PRLFS_MANPAGE='mount.prl_fs.8'

ARCH=$(uname -m)

TGZEXT=tar.gz

# Definition of system directories
BIN_DIR="/usr/bin"
SBIN_DIR="/usr/sbin"
INITD_DIR="/etc/init.d"
INIT_DIR="/etc/init"
TOOLS_CFG_DIR="/etc/prltools"
ICONS_DIR="/usr/share/icons/hicolor"
KERNEL_CONFIG=/boot/config-$(uname -r)
MAN_DIR='/usr/share/man/man8'


# Definition X server configuration variables
XTYPE=""
XVERSION=""
XMODULES_SRC_DIR=""
XMODULES_DIR=""

####################################################################################################
# Definition of X.Org server configuration directories
####################################################################################################

XORG_CONF_DIRS="/etc				 \
		/etc/X11			 \
		/usr/etc			 \
		/usr/etc/X11		 \
		/usr/lib/X11		 \
		/usr/X11R6/etc		 \
		/usr/X11R6/etc/X11	 \
		/usr/X11R6/lib/X11"

XORG_CONF_FILES="xorg.conf xorg.conf-4"

XORG_CONF_DEFAULT="/etc/X11/xorg.conf"

####################################################################################################
# Definition of user space modules
####################################################################################################

TOOLS_X32="prltools"
TOOLS_X64="prltools.x64"

TOOLSD="prltoolsd"
TOOLSD_SERVICE="$BASE_DIR/$TOOLSD.sh"
TOOLSD_ISERVICE="$INITD_DIR/$TOOLSD"

FSMOUNTD='prlfsmountd'

XTOOLS="prl-x11"
XTOOLS_SERVICE="$BASE_DIR/$XTOOLS.sh"
XTOOLS_ISERVICE="$INITD_DIR/$XTOOLS"
XTOOLS_JOB="$BASE_DIR/$XTOOLS.conf"
XTOOLS_INSTALL_JOB="$INIT_DIR/$XTOOLS.conf"
X_EVENT='filesystem'

UTOOLS="prltools_updater"
UTOOLS_SERVICE_INIT="$BASE_DIR/${UTOOLS}_sysv.sh"
UTOOLS_ISERVICE="$INITD_DIR/$UTOOLS"
UTOOLS_JOB="$BASE_DIR/$UTOOLS.conf"
UTOOLS_INSTALL_JOB="$INIT_DIR/$UTOOLS.conf"
SYSD_PATH="/usr/lib/systemd/user"
UTOOLS_SERVICE="$BASE_DIR/$UTOOLS.service"
UTOOLS_INSTALL_SERVICE="$SYSD_PATH/$UTOOLS.service"

CTLCENTER="prlcc"
DNDTOOL="prldnd"
CPTOOL="prlcp"
SGATOOL="prlsga"

HOSTTIME="prlhosttime"
SHOW_VM_CFG="prl_showvmcfg"
NETTOOL="prl_nettool"
SNAPSHOT_TOOL="prl_snapshot"
SHPROF="prlshprof"
SHPRINT="prlshprint"

WMOUSE="prl_wmouse_d"
WMOUSE_LIB="libprl_wmouse_watcher.so"

XORGFIXER="prl-xorgconf-fixer"
OPENGL_SWITCHER="prl-opengl-switcher.sh"
PRLTOOLS_UPDATER="prltools_updater.sh"
TOOLSD_HBR_FILENAME="99prltoolsd-hibernate"

get_lib_dir() {
	libdirs=
	if [ "$ARCH" = "x86_64" ]; then
		# For 64-bit Debian-based systems 64-bit stuff is placed in /lib and
		# /usr/lib. So need to go through _DIRS32 as well.
		# It should be noted that if the system was updated from 32-bit one
		# this code may not work correctly. But it's not clear how it should
		# work in this case.
		libdirs="/usr/lib64 /usr/lib"
	else
		libdirs="/usr/lib"
	fi
	for libdir in $libdirs; do
		if [ -d "$libdir" ]; then
			echo "$libdir"
			exit $E_NOERR
		fi
	done
	perror "Error: could not find system lib directory"
	exit $E_NOXMODIR
}

LIB_DIR=$(get_lib_dir)
LIB_DIR_X32=

####################################################################################################
# Definition of error codes
####################################################################################################

E_NOERROR=0
E_NOACT=161
E_NODIR=162
E_NOXSERV=163
E_NOXMODIR=164
E_NOXMOD=165
E_NOXCONF=166
E_BFAIL=167

####################################################################################################
# Show error
####################################################################################################

perror() {
	echo $1 1>&2
}


update_icon_cache()
{
	# mech is taken from host Linux installers
	if type gtk-update-icon-cache > /dev/null 2>&1; then
		ignore_th_index=
		[ -f "$ICONS_DIR/index.theme" ] || ignore_th_index=--ignore-theme-index
		gtk-update-icon-cache $ignore_th_index -fq "$ICONS_DIR" > /dev/null 2>&1
	fi
}


####################################################################################################
# Remove user space tools' modules
####################################################################################################

remove_tools_modules() {

	skip_xconf_removal=$1

	if [ -e "$TOOLSD_ISERVICE" ]; then
		"$TOOLSD_ISERVICE" stop
		pidfile="/var/run/$TOOLSD.pid"
		if [ -r "$pidfile" ]; then
			# in some versions of tools service there was bug
			# which preveted correct stopping
			# so here is kludge for this situation
			svc_pid=$(< "$pidfile")
			kill $svc_pid
		fi
		"$REGISTER_SERVICE" --remove "$TOOLSD"
		rm -f "$TOOLSD_ISERVICE"
	fi

	if [ -e "$XTOOLS_ISERVICE" ]; then
		"$REGISTER_SERVICE" --remove "$XTOOLS"
		rm -f "$XTOOLS_ISERVICE"
	fi

	if [ -e "$UTOOLS_ISERVICE" ]; then
		"$REGISTER_SERVICE" --remove "$UTOOLS"
		rm -f "$UTOOLS_ISERVICE"
	fi

	type systemctl > /dev/null 2>&1 && [ -d "$SYSD_PATH" ] && 
		systemctl disable "$UTOOLS_INSTALL_SERVICE"

	# kill control all center processes
	for prlcc_pid in $(ps -A -opid,command | grep -v grep | grep "$CTLCENTER\>" | awk '{print $1}'); do
		kill "$prlcc_pid"
	done

	# unload selinux policy
	if [ -e $SLP_BACKUP ]; then
		IFS=$'\n'
		cat "$SLP_BACKUP" | while read mod; do semodule -r $mod; done
		unset IFS
	fi

	#remove shared folder
	mpoint=$(head -n1 $PSF_BACKUP)
	IFS=$'\n'
	cat /proc/mounts | awk '{if ($3 == "prl_fs") print $2}' | \
		while read -r f; do
			mnt_pt=`printf "$f\n"`
			umount "$mnt_pt"
			rmdir "$mnt_pt"
		done
	unset IFS
	umount -at prl_fs
	rmdir "$mpoint"
	# remove fstab entries after tools of version < 9
	sed -i -e 'N;/\n#Parallels.*/d;P;D;' /etc/fstab
	sed -i -e '/prl_fs/d' /etc/fstab
	
	# delete created links on psf on users desktop 
	grep 'Desktop' $PSF_BACKUP | sed 's/\ /\\\ /g' | xargs rm -f

	# Unset parallels OpenGL libraries
	if [ -x "$SBIN_DIR/$OPENGL_SWITCHER" ]; then
		"$SBIN_DIR/$OPENGL_SWITCHER" --off 
	else
		echo "Can not find executable OpenGL switching tool by path $opengl_switcher"
	fi
	
	if [ -e "$TOOLS_BACKUP" ]; then
		echo "Remove tools according to $TOOLS_BACKUP file"
		cat "$TOOLS_BACKUP" | while read line; do
			# Kludge to fix previous buggy backup files on Fedora 19.
			test -f "$line" || line=`echo $line | sed 's/^‘\(.*\)’$/\1/'`
			# Kludge to support case when 64-bit Ubuntu 11.04
			# was updated to 11.10: symlink /usr/lib64 was removed.
			test -f "$line" || line=${line/usr\/lib64/usr\/lib}
			echo " rm $line"
			rm -f "$line"
		done
		rm -f "$TOOLS_BACKUP"
	fi

	# Parallels Tools icon was removed
	# So need to update icon cache
	update_icon_cache

	# Remove directory with extracted prltools.$arch.tar.gz
	# with old modules built for all version of Xorg
	rm -rf "$TOOLS_DIR"
	
	if [ -n "$skip_xconf_removal" ]; then
		echo "Removing of X server configuration is skipped."
		# we also should not delete directory with tools case backups are stored there
		return 0
	fi

	if [ -e "$XCONF_BACKUP" ]; then
		echo "Restore X server configuration file according to $XCONF_BACKUP"
		. "$XCONF_BACKUP"
		if [ -z "$BACKUP_XBCONF" ]; then
			[ -e "$BACKUP_XCONF" ] && rm -f "$BACKUP_XCONF"
		else
			[ -e "$BACKUP_XBCONF" ] && mv -f "$BACKUP_XBCONF" "$BACKUP_XCONF"
		fi
		# Now we do not remove "evdev_drv.so" driver, but previously we could do this.
		# Thus, leave this string for compatibility with previous versions of Guest Tools.
		[ -e "$BACKUP_XBEVDEV" ] && mv -f "$BACKUP_XBEVDEV" "$BACKUP_XEVDEV"
		rm -f "$XCONF_BACKUP"
	fi

	# Per-user cleanup actions:
	for d in $(awk -F: '{print $6}' /etc/passwd); do
		# Restore configuration of users directories after
		# Shared Profile changes.
		for f in user-dirs.dirs gtk-bookmarks; do
			cfg=${d}/.parallels/${f}
			bkp=${cfg}.orig
			if [ -r "$bkp" -a -L "$cfg" ]; then
				cp -f "$bkp" "$cfg"
				rm -f "$cfg" "$bkp"
			fi
		done

		# Cleanup custom monitors configs of dynamic resolution tool.
		rm -f "${d}/.config/monitors.xml"
	done
}


####################################################################################################
# Install user space tools' modules
####################################################################################################

check_x_server_version() {
	XVERSION=$("$DETECT_X_SERVER" -v)
	if [ $? -ne $E_NOERROR ]; then
		XVERSION="6.7"
		return $E_NOXSERV
	fi
	echo $XVERSION
	return $E_NOERROR
}

get_x_server_version() {
	XTYPE="xorg"
	XVERSION=$(check_x_server_version)
	[ $? -ne $E_NOERROR ] && return $E_NOXSERV
	echo "X server: $XTYPE, Version: $XVERSION"
	XMODULES_SRC_DIR=$("$DETECT_X_SERVER" -dsrc "$TOOLS_DIR")
	if [ $? -eq $E_NOERROR ]; then
		echo "System X modules are installing from $XMODULES_SRC_DIR"
	else
		return $E_NOXMODIR
	fi

	XMODULES_DIR=$("$DETECT_X_SERVER" -d)
	if [ $? -eq $E_NOERROR ]; then
		echo "System X modules are placed in $XMODULES_DIR"
	else
		return $E_NOXMODIR
	fi
	return $E_NOERROR
}


get_x_server_version_num() {
	vmajor=$(echo $XVERSION | awk -F . '{ printf "%s", $1 }')
	vminor=$(echo $XVERSION | awk -F . '{ printf "%s", $2 }')
	vpatch=$(echo $XVERSION | awk -F . '{ printf "%s", $3 }')

	if [ "$vmajor" -ge "6" ]; then
	# Must discount major version,
	# because XOrg changes versioning logic since 7.3 (7.3 -> 1.3)
		vmajor=$(($vmajor - 6))
	fi

	v=$(($vmajor*1000000 + $vminor*1000))
	if [ -n "$vpatch" ]; then
		v=$(($v + $vpatch))
	fi
	echo $v
}


# Prints path to X11 configuration file
find_xorgconf() {
	# Starting from Xorg 1.15 all config files should be stored
	# in another place:
	local v=$(get_x_server_version_num)
	if [ $v -ge 1005000 ]; then
		local d='/usr/share/X11/xorg.conf.d'
		if [ -d "$d" ]; then
			echo "$d/40-prltools.conf"
			return
		fi
	fi

	xdir=""
	xcfg=""

	# Search through all possible directories and X server configuration file
	for dir in $XORG_CONF_DIRS; do
		for file in $XORG_CONF_FILES; do
			if [ -e "$dir/$file" ]; then
				xdir="$dir"
				xcfg="$file"
				break 2
			fi
		done
	done

	if ([ -n "$xdir" ] && [ -n "$xcfg" ]); then
		echo "$xdir/$xcfg"
	else
		echo "$XORG_CONF_DEFAULT"
	fi
}

configure_x_server() {

	xconf=`find_xorgconf`
	xbconf=''
	if [ -f "$xconf" ]; then
		xbconf="$BACKUP_DIR/.${xconf##*/}"
		cp -f "$xconf" "$xbconf"

		echo "X server config: $xconf"
	else
		# X server config doesn't exist
		# So value of xbconf will be empty
		echo "X server config: $xconf (doesn't exist)"
	fi

	# ... and save information about X server configuration files
	echo "BACKUP_XCONF=$xconf"	>>	"$XCONF_BACKUP"
	echo "BACKUP_XBCONF=$xbconf"	>>	"$XCONF_BACKUP"

	"$CONFIGURE_X_SERVER" "$XTYPE" "$XVERSION" "$xbconf" "$xconf"
	if [ "x$?" != "x0" ]; then
		cp -f "$xbconf" "$xconf"
		return 1
	fi
}

install_x_modules() {
	xmod="$1/x-server/modules"

	# Link X modules for 6.7 and 6.8 versions of X.Org server
	if ([ "x$XVERSION" = "x6.7" ] || [ "x$XVERSION" = "x6.8" ]); then
		if [ "$ARCH" != "x86_64" ]; then
			xlib="$TOOLS_DIR/lib"
			vdrv="prlvideo_drv"
			xvideo="$xmod/drivers/$vdrv"
			mdrv="prlmouse_drv"
			xmouse="$xmod/input/$mdrv"

			gcc -shared "$xvideo.o" "$xlib/libTISGuest.a" "$xlib/libOTGGuest.a" "$xlib/libBitbox.a" \
				-L"$XMODULES_DIR" -lvbe -lddc -lint10 -lramdac -lfb \
				-Wl,-z -Wl,now -Wl,-soname -Wl,"$vdrv.so" -o "$xvideo.so"

			result=$?
			[ $result -ne $E_NOERROR ] && return $result

			mv -vf "$xvideo.so" "$XMODULES_DIR/drivers" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"

			gcc -shared "$xmouse.o" "$xlib/libTISGuest.a" "$xlib/libOTGGuest.a" "$xlib/libBitbox.a" \
				-Wl,-z -Wl,now -Wl,-soname -Wl,"$mdrv.so" -o "$xmouse.so"

			result=$?
			[ $result -ne $E_NOERROR ] && return $result

			mv -vf "$xmouse.so" "$XMODULES_DIR/input" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
		else
			xlib="$TOOLS_DIR/lib"
			vdrv="prlvideo_drv"
			xvideo="$xmod/drivers/$vdrv"
			mdrv="prlmouse_drv"
			xmouse="$xmod/input/$mdrv"

			gcc -r "$xvideo.o" -nostdlib -o "$xvideo-out.o"

			result=$?
			[ $result -ne $E_NOERROR ] && return $result

			mv -vf "$xvideo-out.o" "$XMODULES_DIR/drivers/$vdrv.o" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"

			gcc -r "$xmouse.o" "$xlib/libTISGuest_nopic.a" "$xlib/libOTGGuest_nopic.a" "$xlib/libBitbox_nopic.a" \
				-nostdlib -o "$xmouse-out.o"

			result=$?
			[ $result -ne $E_NOERROR ] && return $result

			mv -vf "$xmouse-out.o" "$XMODULES_DIR/input/$mdrv.o" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
		fi
	else
		cp -vRf "$xmod/"* "$XMODULES_DIR" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
}

apply_x_modules_fixes() {
	v=$(get_x_server_version_num)
	# Starting from XServer 1.4 we are must configure udev,
	# in this purposes we will setup hall/udev rules

	if [ "$v" -ge "1004000" ]; then
	# Configuring udev via hal scripts

		hal_other="/usr/share/hal/fdi/policy/20thirdparty"
		x11prl="x11-parallels.fdi"

		# Let's set this level, why not!
		level=20
		cp -vf "$TOOL_DIR/$x11prl" "$hal_other/$level-$x11prl" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
	
	if [ "$v" -ge "1007000" ]; then
	# Configuring udev via rules

		udev_dir="/lib/udev/rules.d"
		xorgprlmouse="xorg-prlmouse.rules"
		level=69
		cp -vf "$TOOL_DIR/$xorgprlmouse" "$udev_dir/$level-$xorgprlmouse" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"

		xorgprlmouse="prlmouse.conf"
		level=50
		udev_dir="/usr/lib/X11/xorg.conf.d"
		if test -d "$udev_dir"; then
			cp -vf "$TOOL_DIR/$xorgprlmouse" "$udev_dir/$level-$xorgprlmouse" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
		fi
		udev_dir="/usr/lib64/X11/xorg.conf.d"
		if test -d "$udev_dir"; then
			cp -vf "$TOOL_DIR/$xorgprlmouse" "$udev_dir/$level-$xorgprlmouse" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
		fi
		udev_dir="/usr/share/X11/xorg.conf.d"
		if test -d "$udev_dir"; then
			cp -vf "$TOOL_DIR/$xorgprlmouse" "$udev_dir/$level-$xorgprlmouse" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
		fi
		udev_dir="/etc/X11/xorg.conf.d"
		if test -d "$udev_dir"; then
			cp -vf "$TOOL_DIR/$xorgprlmouse" "$udev_dir/$level-$xorgprlmouse" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
		fi
	fi
}

# Set driver for our device 1ab8:4005 to "prl_tg" if it is "unknown"
# This is to make kudzu happy and not repatch xorg.conf
fix_hwconf() {

	hwconf_file='/etc/sysconfig/hwconf'

	test -r "$hwconf_file" || return

	hwconf_file_content=`< "$hwconf_file"`
	test -z "$hwconf_file_content" && return

	echo "$hwconf_file_content" | awk '
	{
		if ($0 == "-")
		{
			if (NR > 1)
			{
				# One section is already read. Dump it.
				for (i = 0;  i < idx; ++i)
					print items[i]
			}

			# Start reading section
			idx = 0
			class = ""
			device_id = ""
			vendor_id = ""
			driver = ""
			driver_idx = 0
		}
		else
		if ($1 == "class:")
			class = $2
		else
		if ($1 == "vendorId:")
			vendor_id = $2
		else
		if ($1 == "deviceId:")
			device_id = $2
		else
		if ($1 == "driver:")
		{
			driver = $2
			driver_idx = idx
		}

		if (class == "VIDEO" && vendor_id == "1ab8" && device_id == "4005" && driver == "unknown")
		{
			# Section for our video device! Replace driver to prl_tg
			items[driver_idx] = "driver: prl_tg"
			class = ""
		}

		# Appeding item to currect section	
		items[idx] = $0
		++idx
	}

	END {

		# Dumping the very last section
		for (i = 0;  i < idx; ++i)
			print items[i]

	}' > "$hwconf_file"
}


# Setup launcher into users's session in all available DEs
# $1 - path to launcher .desktop-file
setup_session_launcher() {

	autostart_paths="/etc/xdg/autostart
/usr/share/autostart
/usr/share/gnome/autostart
/usr/local/share/autostart
/usr/local/share/gnome/autostart
/opt/gnome/share/autostart
/opt/kde/share/autostart
/opt/kde3/share/autostart
/opt/kde4/share/autostart"

	# Try to use kde-config for KDE if available
	if type kde-config >/dev/null 2>&1; then
		kde_autostart_path="`kde-config --prefix`/share/autostart"
		if ! echo $autostart_paths | grep -q "\<$kde_autostart_paths\>"; then
			autostart_paths="$autostart_paths
$kde_autostart_paths"
		fi
	fi

	symlink_name="${1##*/}"
	for autostart_path in $autostart_paths; do
		if [ -d "$autostart_path" ]; then
			ln -s "$1" "$autostart_path" && \
				echo "${autostart_path}/${symlink_name}" >> "$TOOLS_BACKUP"
		fi
	done
}

install_cpuhotplug_rules()
{
	. "$PMANAGER" >/dev/null 2>&1
	os_name=$(detect_os_name)
	os_version=$(detect_os_version $os_name)
	dst_cpuhotplug_rules="/etc/udev/rules.d/99-parallels-cpu-hotplug.rules"
	os_version=`echo $os_version |	sed 's+.*\.++g'`
	if [ "$os_name" = "redhat" ] && [ "$os_version" -le "5" ]; then
		if [ -r "$KERNEL_CONFIG" ]; then
			cat "$KERNEL_CONFIG" | grep -q "^CONFIG_HOTPLUG_CPU=y"
			[ $? -eq 0 ] && cp -vf "$TOOL_DIR/parallels-cpu-hotplug.rules" "$dst_cpuhotplug_rules"
		fi
	fi
}


install_memory_hotplug_rules()
{
	mem_rule="parallels-memory-hotplug.rules"
	dst_mem_rule="/etc/udev/rules.d/99-$mem_rule"
	grep -qs '^CONFIG_MEMORY_HOTPLUG=y' "$KERNEL_CONFIG" &&
		cp -vf "$TOOL_DIR/$mem_rule" "$dst_mem_rule" | \
			awk '{ print $3 }' | tr -d \`\'>> "$TOOLS_BACKUP"
}


# Updates boot loader configuration
# Current implementation provides only one simple thing:
#  it finds all kernels that don't have 'divider' option
#  and adds 'divider=10' to them.
# Implementation is targeted only for RHEL/CentOS 5.x family.
update_grubconf()
{
	echo "Going to update boot loader cofiguration..."
	grubby_util=/sbin/grubby
	if [ ! -x "$grubby_util" ]; then
		perror "grubby not found"
		return 1
	fi

	grub_conf=/boot/grub/grub.conf
	if [ ! -r "$grub_conf" ]; then
		perror "Cannot find loader conf at path '$grub_conf'"
		return 1
	fi

	grep '^\s*kernel' "$grub_conf" | grep -v divider= | \
		awk '{print $2}' | \
		while read kern; do
			kern="/boot${kern##/boot}"
			[ -f "$kern" ] || continue
			echo " * $kern"
			"$grubby_util" --update-kernel="$kern" --args=divider=10
		done
}

install_selinux_module_make() {
	local makefile="/usr/share/selinux/devel/Makefile"
	local policy=$1
	local mod_name=${policy##*/}; mod_name=${mod_name%.*}

	[ ! -f $makefile ] && return 1

	local tempdir=`mktemp -d /tmp/XXXXXX-parallels-tools-selinux`
	[ -z $tempdir -o ! -d $tempdir	] && return 1
	local mod_pkg="$tempdir/${mod_name}.pp"

	cp ${policy%.*}.* $tempdir
	pushd $tempdir
	make -f $makefile $mod_name.pp
	popd $tempdir
	[ -e "$mod_pkg" ] && semodule -i "$mod_pkg" && \
		echo "$mod_name" >>"$SLP_BACKUP" && \
		restorecon /usr/bin/$TOOLSD && \
		rm -rf $tempdir && return 0
	rm -rf $tempdir
	return 1
}

install_selinux_module() {
	local policy=$1
	local mod_name=${policy##*/}; mod_name=${mod_name%.*}
	local bin_policy="$TOOLS_DIR/${mod_name}.mod"
	local mod_pkg="$TOOLS_DIR/${mod_name}.pp"

	# Check if SELinux stuff is available
	type checkmodule >/dev/null 2>&1 || return 1

	# Build and install module package
	checkmodule -m -M "$policy" -o "$bin_policy"
	[ -e "$bin_policy" ] && semodule_package -m "$bin_policy" -o "$mod_pkg"
	[ -e "$mod_pkg" ] && semodule -i "$mod_pkg" && \
		echo "$mod_name" >>"$SLP_BACKUP" && return 0
	return 1
}

install_tools_modules() {

	skip_xconf=$1

	mkdir -p "$TOOLS_DIR"

	# Unpack user space modules
	tar -xzf "$TOOLS_DIR.$TGZEXT" -C "$TOOLS_DIR"


	# Check XServer version, and is there requires version of X modules?
	get_x_server_version
	result=$?
	
	xmods=$XMODULES_SRC_DIR

	if [ $result -eq $E_NOERROR ]; then

		if [ -z $skip_xconf ]; then
			configure_x_server
			result=$?
			if [ $result -ne $E_NOERROR ]; then
				perror "Error: could not configure X server"
				return $result
			fi
		else
			echo "X server configuration was skipped"
		fi

		install_x_modules $xmods
		result=$?
		if [ $result -ne $E_NOERROR ]; then
			perror "Error: could not install X modules"
			return $result
		fi

		apply_x_modules_fixes
		fix_hwconf
	else
		echo "Skip X server configuration and installation of X modules"
	fi
	
	#prepare for shared folders features using
	if [ -d /media ]; then
		mpoint="/media/psf"
	else
		mpoint="/mnt/psf"
	fi

	echo "$mpoint" > "$PSF_BACKUP"
	
	mkdir -p "$mpoint"
	if [ -d "$mpoint" ]; then
		chmod 0555 "$mpoint"
		install_selinux_module "$PRLFS_SELINUX"

		# add shared mount point to fstab 
		for i in $(awk -F: '{print $6}' /etc/passwd); do 
			if [ -d "$i"/Desktop ]; then
				link_name="$i/Desktop/Parallels Shared Folders"
				ln -s "$mpoint" "$link_name"
				echo "$link_name" >> "$PSF_BACKUP"
			fi
		done	
	fi

	install_selinux_module "$PRLVTG_SELINUX"

	# Install tools' service
	# It is built with xorg.7.1 only
	mkdir -p "$PT_LIB_DIR"
	toolsd="$COMMON_TOOLS_DIR/usr/bin/$TOOLSD"
	if [ -e "$toolsd" ]; then
		# preparation for running prl_wmouse_d from prltoolsd
		# libprl_wmouse_watcher is also built with xorg.7.1 only
		ln -s "$COMMON_TOOLS_DIR/usr/lib/${WMOUSE_LIB}.1.0.0" "$PT_LIB_DIR/$WMOUSE_LIB"
		cp -vf "$xmods/../bin/$WMOUSE" "$BIN_DIR/$WMOUSE" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"

		cp -vf "$toolsd" "$BIN_DIR/$TOOLSD" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"

		cp -f "$TOOLSD_SERVICE" "$TOOLSD_ISERVICE"

		"$REGISTER_SERVICE" --install "$TOOLSD"
		result=$?
		[ $result -ne $E_NOERROR ] && return $result

		# Exclude ne2k-pci module from initramfs image on Debian-based systems
		if type update-initramfs > /dev/null 2>&1; then
			initramfs_hooks_dir=/usr/share/initramfs-tools/hooks
			prl_tools_initramfs_hook_target="$initramfs_hooks_dir/parallels_tools"
			[ -d "$initramfs_hooks_dir" ] &&
				cp -vf "$PRL_TOOLS_INITRAMFS_HOOK" "$prl_tools_initramfs_hook_target" |
					awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
			update-initramfs -u
		fi
	else
		perror "Error: prltoolsd is missed in distribution"
		return 1
	fi
	
	# Install Parallels Shared Folders automount daemon
	fsmountd_src="$BASE_DIR/$FSMOUNTD.sh"
	fsmountd_dst="$BIN_DIR/$FSMOUNTD"
	if [ -e "$fsmountd_src" ]; then
		cp -vf "$fsmountd_src" "$fsmountd_dst" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi

	install_selinux_module_make $PRLTOOLSD_SELINUX

	# Install prl-x11 service
	cp -f "$XTOOLS_SERVICE" "$XTOOLS_ISERVICE"
	# Install prl_updater service for sysV or systemd or upstart
	if type systemctl > /dev/null 2>&1; then
		cp -vf "$UTOOLS_SERVICE" "$UTOOLS_INSTALL_SERVICE" | awk '{print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP" &&
		systemctl enable "$UTOOLS_INSTALL_SERVICE"
	elif type initctl > /dev/null 2>&1; then
		cp -vf "$UTOOLS_JOB" "$UTOOLS_INSTALL_JOB" | awk '{ print $3 }'	| tr -d \`\' >> "$TOOLS_BACKUP" &&
                initctl reload-configuration
	else
		cp -f "$UTOOLS_SERVICE_INIT" "$UTOOLS_ISERVICE" && "$REGISTER_SERVICE" --install "$UTOOLS"
	fi
	# Check if any upstart services emits 'starting-dm' event
	# and use parallels upstart service to start prl-x11 before X service
	# In other cases use chkconfig service that starts in the beginning
	# of startup. Upstart service was implemented only for Ubuntu yet
	[ -d "$INIT_DIR" ] && grep -q -r "$X_EVENT" "$INIT_DIR" &&
			cp -vf "$XTOOLS_JOB" "$XTOOLS_INSTALL_JOB" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP" ||
				"$REGISTER_SERVICE" --install "$XTOOLS"

	# Install Parallels Control Center
	# It is built with xorg-7.1 only
	ctlcenter="$COMMON_TOOLS_DIR/usr/bin/$CTLCENTER"
	if [ -e "$ctlcenter" ]; then
		cp -vf "$ctlcenter" "$BIN_DIR/$CTLCENTER" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
	# and just the same for DnD tool
	dndtool="$COMMON_TOOLS_DIR/usr/bin/$DNDTOOL"
	if [ -e "$dndtool" ]; then
		cp -vf "$dndtool" "$BIN_DIR/$DNDTOOL" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
	# and CP tool as well
	cptool="$COMMON_TOOLS_DIR/usr/bin/$CPTOOL"
	if [ -e "$cptool" ]; then
		cp -vf "$cptool" "$BIN_DIR/$CPTOOL" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
	# and don't forget brand new SGA
	sgatool="$COMMON_TOOLS_DIR/usr/bin/$SGATOOL"
	if [ -e "$sgatool" ]; then
		cp -vf "$sgatool" "$BIN_DIR/$SGATOOL" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi

	if [ -d "$ICONS_DIR" ]; then
		icon="$TOOL_DIR/$TOOLS_ICON"
		icon_target="$ICONS_DIR/48x48/apps/$TOOLS_ICON"
		if [ -e "$icon" ]; then
			cp -vf "$icon" "$icon_target" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
		fi
		update_icon_cache
	fi

	# ... and its laucher.
	# Also need to setup launcher for prl_wmouse_d.
	mkdir -p "$TOOLS_CFG_DIR"
	for desktop_file in "$CTLCENTER_LAUNCHER" "$WMOUSED_LAUNCHER" "$PTIAGENT_LAUNCHER"; do
		launcher="$TOOL_DIR/$desktop_file"
		launcher_target="$TOOLS_CFG_DIR/$desktop_file"
		if [ -e "$launcher" ]; then
			cp -vf "$launcher" "$launcher_target" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
			setup_session_launcher "$launcher_target"
		fi
	done

	# Install Compiz plugin
	libprlcompizdir="$TOOLS_DIR/lib/compiz"
	libprlcompizdir_target="$LIB_DIR/compiz"
	if [ -d "$libprlcompizdir_target" ]; then
		IFS=$'\n'
		for plugin in $(ls -1 "$libprlcompizdir"); do
			if [ -e "$libprlcompizdir/$plugin" ]; then
				cp -vf "$libprlcompizdir/$plugin" "$libprlcompizdir_target/" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
			fi
		done
		unset IFS
	fi

	# Install host time utility
	hostime="$TOOLS_DIR/bin/$HOSTTIME"
	if [ -e "$hostime" ]; then
		cp -vf "$hostime" "$BIN_DIR/$HOSTTIME" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
	
	# Install istatus utility
	show_vm_cfg="$TOOLS_DIR/bin/$SHOW_VM_CFG"
	if [ -e "$show_vm_cfg" ]; then
		cp -vf "$show_vm_cfg" "$BIN_DIR/$SHOW_VM_CFG" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
	
	# Install network tool utility
	nettool="$TOOLS_DIR/sbin/$NETTOOL"
	if [ -e "$nettool" ]; then
		cp -vf "$nettool" "$SBIN_DIR/$NETTOOL" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi

	# Install utility for smoof filesystems backup
	snap_tool="$TOOLS_DIR/sbin/$SNAPSHOT_TOOL"
	if [ -e "$snap_tool" ]; then
		cp -vf "$snap_tool" "$SBIN_DIR/$SNAPSHOT_TOOL" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi

	# Install shared profile tool
	shprof="$TOOLS_DIR/bin/$SHPROF"
	if [ -e "$shprof" ]; then
		cp -vf "$shprof" "$BIN_DIR/$SHPROF" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi

	# Install shared printers tool
	shprint="$TOOLS_DIR/bin/$SHPRINT"
	if [ -e "$shprint" ]; then
		cp -vf "$shprint" "$BIN_DIR/$SHPRINT" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi

	# Install xorg.conf fixer
	xorgfix="$TOOLS_DIR/sbin/$XORGFIXER"
	if [ -e "$xorgfix" ]; then
		cp -vf "$xorgfix" "$SBIN_DIR/$XORGFIXER" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi

	# Install OpenGL switcher
	openglsw="$TOOLS_DIR/sbin/$OPENGL_SWITCHER"
	if [ -e "$openglsw" ]; then
		cp -vf "$openglsw" "$SBIN_DIR/$OPENGL_SWITCHER" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
		
	# Install Parallels Tools updater
	prltoolsup="$TOOLS_DIR/sbin/$PRLTOOLS_UPDATER"
	if [ -e "$prltoolsup" ]; then
		cp -vf "$prltoolsup" "$SBIN_DIR/$PRLTOOLS_UPDATER" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi
	
	# Man-page for prl_fs
	manpage="$TOOL_DIR/$PRLFS_MANPAGE"
	if [ -d "$MAN_DIR" -a -e "$manpage" ]; then
		cp -vf "$manpage" "$MAN_DIR/$PRLFS_MANPAGE" | awk '{ print $3 }' | tr -d \`\' >> "$TOOLS_BACKUP"
	fi

	# For RHEL/CentOS 5.x we need to add special kernel option
	release_file=/etc/redhat-release
	if [ -r "$release_file" ] && \
	   [ `rpm -qf "$release_file" | sed -e "s/.*release-\([0-9]*\).*/\1/g"` -eq 5 ]
	then
		update_grubconf
		rc=$?
		[ $rc -ne 0 ] && perror "Error: failed to update grub.conf"
	fi

	toolsd_hibernate="$TOOL_DIR/$TOOLSD_HBR_FILENAME"
	[ -e $toolsd_hibernate ] && cp -vf "$toolsd_hibernate" "/etc/pm/sleep.d/$TOOLSD_HBR_FILENAME"

	install_cpuhotplug_rules
	install_memory_hotplug_rules

	ptiagent_starter="$TOOL_DIR/../install-gui"
	ptiagent_symlink="$BIN_DIR/ptiagent"
	ln -sf "$ptiagent_starter" "$ptiagent_symlink" && \
		echo "$ptiagent_symlink" >> "$TOOLS_BACKUP"

	[ "$ARCH" = 'x86_64' ] && arch_suffix=64 || arch_suffix=32
	ptiagent_cmd_symlink="$BIN_DIR/ptiagent-cmd"
	ln -sf "$TOOL_DIR/../installer/iagent$arch_suffix/parallels-wrapper" \
			"$ptiagent_cmd_symlink" && \
		echo "$ptiagent_cmd_symlink" >> "$TOOLS_BACKUP"

	return $E_NOERROR
}

####################################################################################################
# Start installation or removal of user space applications and drivers
####################################################################################################

case "$1" in
	-i | --install | --install-skip-xconf | -r | --remove | --remove-skip-xconf)
		# Check directory with tool's modules
		if [ -n "$TOOL_DIR" ]; then
			if [ "$ARCH" = "x86_64" ]; then
				TOOLS_DIR="$TOOL_DIR/$TOOLS_X64"
			else
				TOOLS_DIR="$TOOL_DIR/$TOOLS_X32"
			fi
			COMMON_TOOLS_DIR="$TOOLS_DIR/xorg.7.1"
		else
			perror "Error: directory with tools modules was not specified"
			exit $E_NODIR
		fi

		# Check backup directory
		if [ -z "$BACKUP_DIR" ]; then
			perror "Error: backup directory was not specified"
			exit $E_NODIR
		fi

		skip_xconf=
		if ([ "$1" = "-i" ] || [ "$1" = "--install" ] || [ "$1" = "--install-skip-xconf" ]); then
			act="install"
			sact="installation"
			fact="Installation"
			test "$1" = "--install-skip-xconf" && skip_xconf=1
		else
			act="remove"
			sact="removal"
			fact="Removal"
			test "$1" = "--remove-skip-xconf" && skip_xconf=1
		fi

		echo "Start $sact of user space modules"

		${act}_tools_modules $skip_xconf
		result=$?

		if [ $result -eq $E_NOERROR ]; then
			echo "$fact of user space applications and drivers was finished successfully"
		else
			perror "Error: failed to $act user space applications and drivers"
		fi

		exit $result
		;;

	-c | --check)
		# Check... is there X server?
		check_x_server_version > /dev/null 2>&1
		result=$?

		if [ $result -ne $E_NOERROR ]; then
			if [ "$FLAG_CHECK_ASK" = 'Yes' ]; then
				echo "There is no ability to setup Guest Tools X server modules."
				echo "Would you like to continue installation without these modules?"
				echo -n "Please, answer [yes/No] "

				read ans
				if ([ "x$ans" = "xYes" ] || [ "x$ans" = "xyes" ]); then
					result=$E_NOERROR
				fi
			else
				# Let's install without X modules
				result=$E_NOERROR
			fi
		fi

		exit $result
		;;

	--check-xconf-patched)
		# Check weather xorg.conf is already patched by PT installer or not yet
		check_x_server_version >/dev/null
		rc=$?
		if [ $rc -ne $E_NOERROR ]; then
			echo "Xorg was not found"
			exit $rc
		fi
		xconf=`find_xorgconf`

		# Will return false if there's no info about xorg.conf backup _and_ there's no prlmouse entry
		[ -f "$XCONF_BACKUP" ] || grep -qs '^\W*Driver\W+"prlmouse"' "$xconf" || exit $E_BFAIL

		# Bug in case of presense of smth metioned above - consider xorg.conf is patched
		exit $E_NOERROR
		;;
esac

exit $E_NOACT
