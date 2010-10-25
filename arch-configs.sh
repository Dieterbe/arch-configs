#!/bin/bash
# Written by Dieter Plaetinck
# License: GPLv3

# TODO
# 'cancel' labels in ask_option now mean 'skip', libui.sh's ask_option should return >0 even when you allow skipping

# Notes
# - with 'suffix' we mean only .pac* suffixes
# - creates /etc/<foo>.merged files from pacnew_scripts (if found) (but should clean them up)

source /usr/lib/libui.sh


search_method=find
do_pacnew=1
do_pacsave=1

usage () {
	echo "$0 <options>

	-l use locate instead of find (it's your job to update the database)
	I assumed this method would be faster, but practice proves me wrong.

	-n process only pacnew files
	-s process only pacsave files

	-h usage (this)"
	exit 0
}

while getopts "lnsh" OPTION
do
	case $OPTION in
	l)
		search_method=locate
		;;
	h)
		usage
		;;
	n)
		do_pacsave=0
		;;
	s)
		do_pacnew=0
		;;
        esac
done

[ $EUID -eq 0 ] || die_error "Gotta be root"
[ -n "$EDITOR" ] && which "$EDITOR" >/dev/null || die_error "Set your \$EDITOR/\$PATH correctly.  Do you want a punch in the face?"

# $1 suffix (ie: .pacnew)
# sets $files
find_files () {
	suffix=$1
	if [ "$search_method" = 'find' ]
	then
		files=($(find /boot /etc -name "*$suffix" || die_error "Find failed"))
	else
		files=($(locate $suffix | egrep '^/(boot|etc)'))
	fi
}

# $1: suffixed filename (= new)
introduce_new_file () {
	echo "****** $1 ******"
	if [ ! -e "$1" ]
	then
		show_warning "File vanished" "$1 vanished.  Skipping this entry.  Are you using an outdated locate database?"
		return 1
	fi
	return 0
}

# $1 suffixed filename (= new)
# sets $old
get_old_file () {
	old=$(echo "$1" | sed 's/\.pac\(new\|save\)$//')
}

# $1: unsuffixed filename (=old)
introduce_old_file () {
	[ -z "$old" ] && die_error "No \$old variable set when calling introduce_old_file"
	if [ ! -e "$old" ]
	then
		show_warning "File vanished" "$old vanished.  You don't see this very often.."
		if ask_yesno "Move $new $old?" yes
		then
			if ! mv $new $old
			then
				show_warning "Move error" "Could not mv $new $old"
				return 1
			fi
		fi
	fi
	return 0
}

# $1 unsuffixed filename
# exit(0) -> helper found, name in $helper
find_pacnew_helper () {
	old=$1
	helper=merge_pacnew_$(basename $old | sed 's/\./_/g')
	which $helper &>/dev/null
}

# $1 old
# $2 new
delete_if_equal () {
	[ -n "$1" -a -n "$2" -a -e "$1" -a -e "$2" ] || die_error "delete_if_equal \$1 and \$2 must be two existing files.  Not $1 and $2"
	if [ "$1" = "$2" ]
	then
		die_error "BUG: delete_if_equal called with equal arguments (twice $1)"
	fi
	old=`readlink -f "$1"`
	new=`readlink -f "$2"`
	if [ "$1" = "$2" ]
	then
		show_warning 'Symlink detected' "$1 and $2 actually point to the same file, $old.  Skipping"
		return 0
	fi
	if [ "$1" -ef "$2" ]
	then
		show_warning 'Symlink detected' "$1 and $2 are actually the same file, $old.  Skipping"
		return 0
	fi
	md5_old=`md5sum "$1" | cut -f1 -d ' '`
	md5_new=`md5sum "$2" | cut -f1 -d ' '`
	if [ "$md5_new" = "$md5_old" ]
	then
		echo "Files $1 and $2 are equal.  Deleting $2"
		if rm "$2"
		then
			echo 'deleted'
		else
			show_warning "Delete error" "Could not rm $2"
			return 1
		fi
	else
		echo "Files $1 and $2 are different."
	fi
	return 0
}

# $1 old
# $2 new
interactive_handle_two () {
	local old=$1
	local new=$2
	delete_if_equal "$old" "$new"
	[ -e "$new" ] || return 0

	# is there a way in vimdiff to say "move all changes from this one into the other" (not dp]cdp]cdp]cdp]cdp)?
	# that way you could do everything in vimdiff instead of using this menu
	while ask_option no 'What to do' '' required vd "vimdiff $old $new" mv "mv $new $old" rm "rm $new"
	do
		case "$ANSWER_OPTION" in
			vd)
				vimdiff "$old" "$new"
				delete_if_equal "$old" "$new" ;;
			mv)
				if ! mv "$new" "$old"
				then
					show_warning "Move error" "Could not mv $new $old"
					return 1
				fi
				;;
			rm)
				if ! rm "$new"
				then
					show_warning "Delete error" "Could not rm $new"
					return 1
				fi
				;;
		esac
		[ -e "$new" ] || return 0
	done
	return 0
}

# $1 old
# $2 new
interactive_handle_one () {
	local old=$1
	local new=$2
	[ -n "$new" -a -e "$new" ] || die_error "interactive_handle_one called with empty/non-existing \$new: $new"
	[ -e "$old" ] && die_error "$old exists (or empty)? interactive_handle_one is supposed to handle only $new"
	while ask_option no "What to do on $new?" "$old does not exist, what do you want to do with $new?" required e "view/edit with $EDITOR" r 'remove'
	do
		case "$ANSWER_OPTION" in
		e)
			$EDITOR "$new" ;;
		r)
			if ! rm "$new"
			then
				show_warning "Delete error" "Could not rm $new"
				return 1
			fi
			;;
		esac
		[ -e "$new" ] || continue
	done
	return 0
}

# $1 old
# $2 new
interactive_handler () {
	local old=$1
	local new=$2
	[ -n "$old" -a -e "$old" ] || die_error "interactive_handler called with empty/non-existing \$old: $old"
	[ -n "$new" -a -e "$new" ] || die_error "interactive_handler called with empty/non-existing \$new: $new"
	if find_pacnew_helper "$old"
	then
		echo "Helper $helper is available. running it.."
		$helper "$old" -c
		$helper "$old" > "$old".merged
		interactive_handle_two "$old" "$old".merged
		if [ -e "$old".merged ] && ! rm "$old".merged
		then
			show_warning "Delete error" "Could not rm $old.merged"
		fi
		# instead of asking "delete .pacnew" and if not "what do you want to do with it" we might just as well do this
		interactive_handle_two "$old" "$new"
	else
		interactive_handle_two "$old" "$new"
	fi
}

if [ $do_pacnew -eq 1 ];
then
	find_files .pacnew
	for new in "${files[@]}"
	do
		introduce_new_file "$new" || continue
		get_old_file "$new"
		introduce_old_file "$new"
		[ -e "$new" ] || continue

		interactive_handler "$old" "$new"
	done
fi

if [ $do_pacsave -eq 1 ];
then
	find_files .pacsave
	# semantically not correct, but for simplicity's sake we call the pacsave files 'new'
	for new in "${files[@]}"
	do
		introduce_new_file "$new" || continue
		get_old_file "$new"
		[ -e "$new" ] || continue
		if [ -e "$old" ] # you probably don't have $old, unless you reinstalled the package after removing it
		then
			interactive_handler "$old" "$new"
		else
			interactive_handle_one "$old" "$new"
		fi
	done
fi

