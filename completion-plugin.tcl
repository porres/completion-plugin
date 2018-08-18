# Copyright (c) 2011 yvan volochine <yvan.volochine@gmail.com>
#
# This file is part of completion-plugin.
#
# completion-plugin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# META NAME completion plugin
# META DESCRIPTION enables completion for objects
# META AUTHOR <Yvan Volochine> yvan.volochine@gmail.com
# META VERSION 0.42

# TODO
# - add user arguments (tabread $1 ...)

# The original version was developed by Yvan Volochine a long ago (as the time of writing: 7 years ago)
# I then embraced the project and i'm willing to mantain it for as long as i can. 
# Right now i'm kind of new to .tcl so i'm trying to stay true to the original code.
# When reasonable i will comment talking about changes i did and why.
#
# https://github.com/HenriAugusto/completion-plugin
#
# Henri Augusto


package require Tcl 8.5
package require pd_menucommands 0.1

namespace eval ::completion:: {
    variable ::completion::config
    variable external_filetype ""
}

###########################################################
# overwritten
rename pdtk_text_editing pdtk_text_editing_old
#rename ::dialog_font::ok ::dialog_font::ok_old ;#now that we have an settings window we don't need that

############################################################
# GLOBALS

# default
set ::completion::config(save_mode) 1 ;# save keywords (s/r/array/table/...)
set ::completion::config(max_lines) 20
set ::completion::config(font) "DejaVu Sans Mono"
set ::completion::config(font_size) 8 ;# FIXME ???
set ::completion::config(bg) "#0a85fe"
set ::completion::config(skipbg) "#0ad871"
set ::completion::config(monobg) "#9832ff"
set ::completion::config(fg) white
set ::completion::config(offset) 0
set ::completion::config(max_scan_depth) 1
set ::completion::config(auto_complete_libs) 1

# some nice colors to try
#0a85fe   #0ad871   #9832ff

#ff9831   #ff00ee   #012345 #this one is great

# private
set ::toplevel ""
set ::current_canvas ""
set ::current_tag ""
set ::current_text ""
set ::erase_text ""
set ::completions {"(empty)"}
set ::new_object false
set ::editx 0
set ::edity 0
set ::focus ""
set ::completion_text_updated 0
set ::is_shift_down 0
set ::is_ctrl_down 0
set ::is_alt_down 0
# =========== [DEBUG mode on/off] ============
#1 = true 0 = false
set ::completion_debug 0 ;
# debug categories
set ::debug_loaded_externals 1 ;#prints loaded externals
set ::debug_entering_procs 1 ;#prints a message when entering a proc
set ::debug_key_event 1 ;#prints a message when a key event is processed
set ::debug_searches 1 ;#messages about the performed searches
set ::debug_popup_gui 1 ;#messages related to the popup containing the code suggestions
set ::debug_char_manipulation 1 ;#messages related to what we are doing with the text on the obj boxes (inserting/deleting chars)
set ::debug_unique_names 1 ;#messages related to storing [send/receive] names [tabread] names and alike.
set ::debug_settings 1 ;#messages related to storing [send/receive] names [tabread] names and alike.

#0 = normal
#1 = skipping
#2 = monolithic
set ::current_search_mode 0

# all pd VANILLA objects
set ::all_externals {hslider vslider bng cnv bang float symbol int send receive select route pack unpack trigger spigot moses until print makefilename change swap value \
    list {list append} {list fromsybmol} {list length} {list prepend} {list split} {list store} {list tosymbol} {list trim} delay metro line timer cputime realtime \
    pipe + - * / pow == != > < >= <= & && | || % << >> mtof powtodb rmstodb ftom dbtopow dbtorms mod div sin cos tan atan atan2 sqrt log exp abs random max min clip wrap notein ctlin \
    pgmin bendin touchin polytouchin midiin sysexin midirealtimein midiclkin noteout ctlout pgmout bendout touchout polytouchout midiout makenote stripnote \
    oscparse oscformat tabread tabread4 tabwrite soundfiler table array loadbang netsend netreceive glist textfile text openpanel savepanel bag poly key keyup keyname \
    declare +~ -~ *~ /~ max~ min~ clip~ sqrt~ rsqrt~ q8_sqrt~ q8_rsqrt~ wrap~ fft~ ifft~ rfft~ rifft~ pow~ log~ exp~ abs~ framp~ mtof~ ftom~ rmstodb~ dbtorms~ dac~ adc~ sig~ line~ vline~ \
    threshdold~ snapshot~ vsnapshot~ bang~ samplerate~ send~ receive~ throw~ catch~ block~ switch~ readsf~ writesf~ phasor~ cos~ osc~ tabwrite~ tabplay~ tabread~ tabread4~ tabosc4~ tabsend~ \
    tabreceive~ vcf~ noise~ env~ hip~ lop~ bp~ biquad~ samphold~ print~ rpole~ rzero~ rzero_rev~ cpole~ czero~ czero_rev~ delwrite~ delread~ delread4~ vd~ inlet outlet inlet~ outlet~ clone \
    struct drawcurve filledcurve drawpolygon filledpolygon plot drawnumber drawsymbol pointer get set element getsize setsize append scalar sigmund~ bonk~ choice hilbert~ complet-mod~ \
    expr expr~ fexpr~ loop~ lrshift~ pd~ stdout~ rev1~ rev2~ rev3~ bob~}

set ::monolithic_externals {}

#useful function for debugging
proc ::completion::debug_msg {dbgMsg {debugKey "none"}} {
    switch -- $debugKey {
        "none" {}
        "loaded_externals" { if { !$::debug_loaded_externals } { return  } }
        "entering_procs" { if { !$::debug_entering_procs } { return  } }
        "key_event" { if { !$::debug_key_event } { return  } }
        "searches" { if { !$::debug_searches } { return  } }
        "popup_gui" { if { !$::debug_popup_gui } { return  } }
        "char_manipulation" { if { !$::debug_char_manipulation } { return  } }
        "unique_names" { if { !$::debug_unique_names } { return  } }
        "settings" { if { !$::debug_settings } { return  } }
    }
    if { $::completion_debug } {
        ::pdwindow::post "autocmpl_dbg: $dbgMsg\n"
    }
}

# This function sends keydown messages to pd
# It is better to use a separate function instead of hardcoded pdsend messages like Yvan was doing because the pd tcl api might change. 
# In fact when i took the project that was one of the major bugs with it. It was using pdsend "pd key 1 $keynum 0" which where not working.
# So using functions (procs) promotes mantainability because you only have to change their implementation to fix the code after api changes.
proc ::completion::sendKeyDown {keynum} {
    pdsend "[winfo toplevel $::current_canvas] key 1 $keynum 0"
}

# This function sends keydown and then keyup messages to pd
proc ::completion::sendKeyDownAndUp {keynum} {
    pdsend "[winfo toplevel $::current_canvas] key 1 $keynum 0"
    pdsend "[winfo toplevel $::current_canvas] key 0 $keynum 0"
}

#Henri: reads the files located in each extra folder in order to add them
proc ::completion::read_extras_henri {} {
    ::completion::debug_msg "sys_searchpath = $::sys_searchpath"
    set i 0
    foreach folder $::sys_searchpath {
        #::completion::debug_msg "folder $i"
        #::completion::debug_msg "$folder"
        set files [glob -directory -nocomplain $folder *.pd]
        #::completion::debug_msg "files = $files"
        incr i
    }
    #::completion::debug_msg [lindex $::sys_searchpath 0]
}

#called once upon plugin initialization
proc ::completion::init {} {
    variable external_filetype
    ::completion::read_config
    #::completion::read_extras
    switch -- $::windowingsystem {
        "aqua"  { set external_filetype *.pd_darwin }
        "win32" { set external_filetype *.dll}
        "x11"   { set external_filetype *.pd_linux }
    }
    bind all <Tab> {+::completion::trigger}
    ::completion::add_user_externals
    #::completion::add_libraries_externals_from_startup_flags
    ::completion::add_user_customcompletions
    ::completion::add_user_monolithiclist
    ::completion::init_menu
    set ::all_externals [lsort $::all_externals]
}

proc ::completion::init_menu {} {
    if {$::windowingsystem eq "aqua"} {
        set mymenu .menubar.apple.preferences
    } else {
        set mymenu .menubar.edit.preferences    
    }
    
    if { [catch {
        $mymenu entryconfigure [_ "AutoComplete Settings"] -command {::completion::show_options_gui}
    } _ ] } {
        $mymenu add separator
        $mymenu add command -label [_ "AutoComplete Settings"] -command {::completion::show_options_gui}
    }
}

proc ::completion::show_options_gui {} {
    if {[winfo exists .options]} {
        focus .options
        return
    }
    toplevel .options
    wm title .options "Pd AutoComplete Settings"

    frame .options.f -padx 5 -pady 5
    label .options.f.title_label -text "PD AutoComplete Settings"
    .options.f.title_label configure -font [list $::completion::config(font) [expr {$::completion::config(font_size)+3}]]
    
    label .options.f.status_label -text "" -foreground "#cc2222"

    # COLORS
    #note that we are using KeyRelease bindings because using "-validate key" would not validate in the right time.
    #ex: you would type a valid string #aabbcc and it would be invalid. Then on the next keypress (whichever it was) it would process #aabbcc

    #Options for background color
    label .options.f.click_to_choose_label -text "click to\nchoose"
    
    label .options.f.bg_label -text "bkg color"
    entry .options.f.bg_entry -width 8
    frame .options.f.bg_demo -background $::completion::config(bg) -width 40 -height 40
        bind .options.f.bg_demo <ButtonRelease> { ::completion::user_select_color "bg"}
    bind .options.f.bg_entry <KeyRelease> { ::completion::gui_options_update_color ".options.f.bg_entry" ".options.f.bg_demo" "bg" }
    

    #Options for skipping mode background color
    label .options.f.skip_bg_label -text "skipping bkg color"
    entry .options.f.skip_bg_entry -width 8
    frame .options.f.skip_bg_demo -background $::completion::config(skipbg) -width 40 -height 40
        bind .options.f.skip_bg_demo <ButtonRelease> { ::completion::user_select_color "skipbg"}
    bind .options.f.skip_bg_entry <KeyRelease> { ::completion::gui_options_update_color ".options.f.skip_bg_entry" ".options.f.skip_bg_demo" "skipbg" }
    
    #Options for monolithic mode background color
    label .options.f.mono_bg_label -text "mono-object bkg color"
    entry .options.f.mono_bg_entry -width 8
    frame .options.f.mono_bg_demo -background $::completion::config(monobg) -width 40 -height 40
        bind .options.f.mono_bg_demo <ButtonRelease> { ::completion::user_select_color "monobg"}
    bind .options.f.mono_bg_entry <KeyRelease> { ::completion::gui_options_update_color ".options.f.mono_bg_entry" ".options.f.mono_bg_demo" "monobg" }
    

    #Misc
    checkbutton .options.f.auto_complete_libs -variable ::completion::config(auto_complete_libs) -onvalue 1 -offvalue 0
    label .options.f.auto_complete_libs_label -text "auto complete library names"

    spinbox .options.f.number_of_lines -width 6 -from 3 -to 30 -textvariable ::completion::config(max_lines)
    label .options.f.number_of_lines_label -text "number of lines to display"
    
    spinbox .options.f.maximum_scan_depth -width 6 -from 0 -to 10 -textvariable ::completion::config(max_scan_depth)
    label .options.f.maximum_scan_depth_label -text "maximum scan depth"

    spinbox .options.f.font_size -width 6 -from 7 -to 20 -textvariable ::completion::config(font_size)
    label .options.f.font_size_label -text "font size"
    
    #Buttons
    button .options.f.save_btn -text "save to file" -command ::completion::write_config
    button .options.f.default_btn -text "default" -command ::completion::restore_default_option

    set padding 2

    # ::::GRID::::

    #setup main frame stuff
    grid .options.f -column 0 -row 0
    grid .options.f.title_label -column 0 -row 0 -columnspan 3 -padx $padding -pady $padding

    #setup the rest
    set current_row 1

    #auto complete libs
    grid .options.f.auto_complete_libs_label -column 0 -row $current_row -padx $padding -pady $padding -sticky "e"
    grid .options.f.auto_complete_libs -column 1 -row $current_row -padx $padding -pady $padding -sticky "w"
    incr current_row

    #number of lines
    grid .options.f.number_of_lines_label -column 0 -row $current_row -padx $padding -pady $padding -sticky "e"
    grid .options.f.number_of_lines -column 1 -row $current_row -padx $padding -pady $padding -sticky "w"
    incr current_row

    #font size
    grid .options.f.font_size_label -column 0 -row $current_row -padx $padding -pady $padding -sticky "e"
    grid .options.f.font_size -column 1 -row $current_row -padx $padding -pady $padding -sticky "w"
    incr current_row

    #maximum scan depth
    grid .options.f.maximum_scan_depth_label -column 0 -row $current_row -padx $padding -pady $padding -sticky "e"
    grid .options.f.maximum_scan_depth -column 1 -row $current_row -padx $padding -pady $padding -sticky "w"

    grid .options.f.click_to_choose_label -column 2 -row $current_row -padx $padding -pady $padding
    incr current_row

    # change background color
    grid .options.f.bg_label -column 0 -row $current_row -padx $padding -pady $padding -sticky "e"
    grid .options.f.bg_entry -column 1 -row $current_row -padx $padding -pady $padding -sticky "w"
    grid .options.f.bg_demo -column 2 -row $current_row -padx $padding -pady $padding
    incr current_row

    # change skip mode background color
    grid .options.f.skip_bg_label -column 0 -row $current_row -padx $padding -pady $padding -sticky "e"
    grid .options.f.skip_bg_entry -column 1 -row $current_row -padx $padding -pady $padding -sticky "w"
    grid .options.f.skip_bg_demo -column 2 -row $current_row -padx $padding -pady $padding
    incr current_row

    # change mono mode background color
    grid .options.f.mono_bg_label -column 0 -row $current_row -padx $padding -pady $padding -sticky "e"
    grid .options.f.mono_bg_entry -column 1 -row $current_row -padx $padding -pady $padding -sticky "w"
    grid .options.f.mono_bg_demo -column 2 -row $current_row -padx $padding -pady $padding
    incr current_row
    
    grid .options.f.status_label -column 0 -row $current_row -padx $padding -pady 8 -sticky "e"
    grid .options.f.default_btn -column 1 -row $current_row -padx $padding -pady 8 -sticky "e"
    grid .options.f.save_btn -column 2 -row $current_row -padx $padding -pady 8 -sticky "w"
    incr current_row

    ::completion::update_options_gui
}

proc ::completion::update_options_gui {} {
    .options.f.status_label configure -text ""
    .options.f.bg_demo configure -background $::completion::config(bg)
    .options.f.skip_bg_demo configure -background $::completion::config(skipbg)
    .options.f.mono_bg_demo configure -background $::completion::config(monobg)
    .options.f.bg_entry delete 0 end
    .options.f.bg_entry insert 0 $::completion::config(bg)
    .options.f.skip_bg_entry delete 0 end
    .options.f.skip_bg_entry insert 0 $::completion::config(skipbg)
    .options.f.mono_bg_entry delete 0 end
    .options.f.mono_bg_entry insert 0 $::completion::config(monobg)
}

proc ::completion::restore_default_option {} {
    set ::completion::config(max_lines) 20
    set ::completion::config(font) "DejaVu Sans Mono"
    set ::completion::config(font_size) 8
    set ::completion::config(bg) "#0a85fe"
    set ::completion::config(skipbg) "#0ad871"
    set ::completion::config(monobg) "#9832ff"
    set ::completion::config(fg) white
    set ::completion::config(offset) 0
    set ::completion::config(max_scan_depth) 1
    set ::completion::config(auto_complete_libs) 1
    ::completion::update_options_gui
}

proc ::completion::gui_options_update_color {entryWidget frameWidget configTag} {
    if { [regexp {^\#(\d|[a-f]){6}$} [$entryWidget get]] } {
        set ::completion::config($configTag) [$entryWidget get]
        $frameWidget configure -background $::completion::config($configTag)
        # chagne color to show it's valid
        $entryWidget configure -foreground #000000
    } else {
        # chagne color to show it's INvalid
        $entryWidget configure -foreground #de2233
    }
}

# taken from kiosk-plugin.tcl by Iohannes
proc ::completion::read_config {{filename completion.cfg}} {
    if {[file exists $filename]} {
        set fp [open $filename r]
    } else {
        set filename [file join $::current_plugin_loadpath $filename]
        if {[file exists $filename]} {
            set fp [open $filename r]
        } else {
            ::completion::debug_msg "completion.cfg not found"
            return False
        }
    }
    while {![eof $fp]} {
        set data [gets $fp]
        if { ![regexp {^\w} $data] } {
            continue ;#this line doesn't start with a char
        }
        # if the user provided the key value pair
        ::completion::debug_msg "data length = [llength $data]" "settings"
        if { [llength $data ] == 2} {
            set ::completion::config([lindex $data 0]) [lindex $data 1]
            ::completion::debug_msg "::completion::config([lindex $data 0]) = $::completion::config([lindex $data 0])" "settings"
        } elseif { [llength $data ] > 2} {
            set ::completion::config([lindex $data 0]) [lrange $data 1 end]
            ::completion::debug_msg "::completion::config([lindex $data 0]) = $::completion::config([lindex $data 0])" "settings"
        } else {
            ::completion::debug_msg "ERROR reading ::completion::config([lindex $data 0]) => data = $data" "settings"
        }
    }
    close $fp
    return True
}

proc ::completion::write_config {{filename completion.cfg}} {
    if {[file exists $filename]} {
    } else {
        set filename [file join $::current_plugin_loadpath $filename]
        if {[file exists $filename]} {
            set fp [open $filename r]
            set had_to_create_file false
        } else {
            set fp [open $filename w+]
            set had_to_create_file true ;#file will get overwritten so we need to append to $lines
        }
    }
    #read the lines from the file
    set lines [split [read $fp] "\n"]
    close $fp

    #process the lines
    set lines [::completion::write_config_variable $lines "max_lines"]
    set lines [::completion::write_config_variable $lines "font"]
    set lines [::completion::write_config_variable $lines "font_size"]
    set lines [::completion::write_config_variable $lines "max_scan_depth"]
    set lines [::completion::write_config_variable $lines "auto_complete_libs"]
    set lines [::completion::write_config_variable $lines "bg"]
    set lines [::completion::write_config_variable $lines "fg"]
    set lines [::completion::write_config_variable $lines "skipbg"]
    set lines [::completion::write_config_variable $lines "monobg"]
    set lines [::completion::write_config_variable $lines "offset"]

    #write the file
    set fp [open $filename w]
    if { $had_to_create_file } {
        set lines [linsert $lines 0 "This file was generated by PD AutoComplete in the absence of the original file that comes with the plugin.\n"]
    }
    puts $fp [join $lines "\n"]
    close $fp
    #.options.f.status_label configure -text "saved!"
    #after 1000 { .options.f.status_label configure -text "" }
}

proc ::completion::write_config_variable {file_lines name} {
    #https://stackoverflow.com/a/37812995/5818209   for writing to specific lines
    ::completion::debug_msg "Saving config($name)" "settings"
    set pattern ^$name\\s ;# do NOT enclose this in brackets
    ::completion::debug_msg "pattern = $pattern" "settings"
    set index 0
    set found false
    foreach line $file_lines {
        #::completion::debug_msg "line = $line"
        if {[regexp $pattern $line]} {
            ::completion::debug_msg "current variable's line = $line" "settings"
            set file_lines [lreplace $file_lines $index $index "$name $::completion::config($name)"]
            ::completion::debug_msg "line AFTER = $line" "settings"
            set found true
        }
        incr index
    }
    if { !$found } {
        #if there is no line for that variable, write it
        lappend file_lines "$name $::completion::config($name)"
    }
    return $file_lines
}

proc ::completion::user_select_color {target} {
    set color [tk_chooseColor -title "AutoComplete settings: Choose a color" -initialcolor $::completion::config($target)]
    if { $color eq ""} { return }
    set ::completion::config($target) $color
    ::completion::update_options_gui
}

#this function looks for objects in the current folder and recursively call itself for each subfolder
#we read the subfolders because pd reads the subpatches!
proc ::completion::add_user_externalsOnFolder {{dir .} depth} {
    variable external_filetype
    if { [expr {$depth > $::completion::config(max_scan_depth)}] } {
        return
    }
    #::completion::debug_msg "external_filetype = $external_filetype" ;#just for debugging
    ::completion::debug_msg "===add_user_externalsOnFolder $dir===" "loaded_externals"
    ::completion::debug_msg "depth =  $depth" "loaded_externals"

    # i concatenate the result of two globs because for some reason i can't use glob with two patterns. I've tried using: {$external_filetype,*.pd}
    # list of pd files on the folder
    set pd_files [glob -directory $dir -nocomplain -types {f} -- *.pd] 
    #List of system depentent (*.pd_darwin, *.dll, *.pd_linux) files on the folder
    set sys_dependent_files [glob -directory $dir -nocomplain -types {f} -- $external_filetype]
    set all_files [concat $pd_files $sys_dependent_files]
    # for both types of files
    foreach filepath $all_files {
        ::completion::debug_msg "     external = $filepath" "loaded_externals"
        set file_tail [file tail $filepath] ;#this one contains the file extension
        set name_without_extension [file rootname $file_tail]
        set dir_name [file dirname $filepath] 
        set how_many_folders_to_get [expr {$depth+0}]
        set folder_name [lrange [file split $filepath] end-$how_many_folders_to_get end-1 ]
        set extension_path [join $folder_name \/]
        if {$extension_path ne ""} {
            set extension_path $extension_path\/
        }
            ::completion::debug_msg "       depth =  $depth" "loaded_externals"
            ::completion::debug_msg "       filepath = $filepath" "loaded_externals"
            ::completion::debug_msg "       dir_name = $dir_name" "loaded_externals"
            ::completion::debug_msg "       folder_name = $folder_name" "loaded_externals"
            ::completion::debug_msg "       extension_path = $extension_path" "loaded_externals"
            ::completion::debug_msg "       file_tail = $file_tail" "loaded_externals"
            ::completion::debug_msg "       name_without_extension = $name_without_extension" "loaded_externals"
        if {[string range $name_without_extension end-4 end] ne "-help"} {
            lappend ::all_externals $extension_path$name_without_extension
        }
    }
    #do the same for each subfolder (recursively)
    set depth [expr {$depth+1}]
    foreach subdir [glob -nocomplain -directory $dir -type d *] {
        ::completion::add_user_externalsOnFolder $subdir $depth
    }
}

# this proc runs the main search ::completion::add_user_externalsOnFolder into each main folder
proc ::completion::add_user_externals {} {
    ::completion::debug_msg "-----searching externals on the following directories:-----" "loaded_externals"
    foreach DIR $::sys_searchpath {
        ::completion::debug_msg "$DIR" "loaded_externals"
    }
    foreach DIR $::sys_staticpath {
        ::completion::debug_msg "static path $DIR" "loaded_externals"
    }
    #for each directory the user set in edit->preferences->path
    set dynamic_and_static_paths [concat $::sys_searchpath $::sys_staticpath]
    set pathlist $::sys_staticpath
    set pathlist $dynamic_and_static_paths
    foreach pathdir $pathlist {
        set dir [file normalize $pathdir]
        if { ! [file isdirectory $dir]} { ;#why Yvan was doing this check?
            continue
        }
        ::completion::add_user_externalsOnFolder $pathdir 0
        #foreach subdir [glob -directory $dir -nocomplain -types {d} *] {
        #    ::completion::add_user_externalsOnFolder $subdir 1
        #}
    }
}

# Reads objects from libs declared with startup flags (does anybody still use this?)
# Deprecated: we don't read from "extra_objects" anymore
proc ::completion::add_libraries_externals_from_startup_flags {} {
    ::completion::debug_msg "entering add libraries externals" "entering_procs"
    #::completion::debug_msg "::startup_libraries = $::startup_libraries"
    foreach lib $::startup_libraries {
        ::completion::debug_msg "lib = $lib" "loaded_externals"
        set filename [file join $::current_plugin_loadpath "extra_objects" $lib]
        ::completion::read_completionslist_file [format "%s.txt" $filename]
    }
}

#adds any completion set in any txt file under "custom_completions"
proc ::completion::add_user_customcompletions {} {
    ::completion::debug_msg "entering add user object list" "entering_procs"
    set userdir [file join $::current_plugin_loadpath "custom_completions"]
    foreach filename [glob -directory $userdir -nocomplain -types {f} -- \
                         *.txt] {
        ::completion::read_completionslist_file $filename
    }
}

#reads objects stored into monolithic files (*.pd_darwin, *.dll, *.pd_linux)
proc ::completion::add_user_monolithiclist {} {
    ::completion::debug_msg "entering add user monolithic list" "entering_procs"
    set userdir [file join $::current_plugin_loadpath "monolithic_objects"]
    # for each .txt file in /monolithic_objects
    foreach filename [glob -directory $userdir -nocomplain -types {f} -- \
                         *.txt] {
        #  Slurp up the data file
        set fp [open $filename r]
        set file_data [read $fp]
        foreach line $file_data {
            #::completion::debug_msg "line = $line"
            lappend ::monolithic_externals [split $line /]
        }
        close $fp
        ::completion::debug_msg "======monolithic=======\n$::monolithic_externals" "loaded_externals"
    }
}

# Reads anything located in the .txt files in the subfolders
proc ::completion::read_completionslist_file {afile} {
    if {[file exists $afile]
        && [file readable $afile]
    } {
        set fl [open $afile r]
        while {[gets $fl line] >= 0} {
            if {[string index $line 0] ne ";"
                && [string index $line 0] ne " "
                && [string index $line 0] ne ""
                && [lsearch -exact $::all_externals $line] == -1} {
                lappend ::all_externals $line
            }
        }
        close $fl
    }
}

# this is called when the user enters the auto completion mode
proc ::completion::trigger {} {
    ::completion::debug_msg "===entering trigger===" "entering_procs"
    set ::is_shift_down 0
    set ::is_ctrl_down 0
    set ::is_alt_down 0
    if {$::current_canvas ne ""
        && $::current_text eq ""
        && ! $::completion_text_updated
    } {
        #this code is responsible for reading any text already present in the object when you enter the autocomplete mode
        set ::current_text \
            [$::current_canvas itemcget $::current_tag -text]
        ::completion::trimspaces
        ::completion::debug_msg "Text that was already in the box = $::current_text\n" "searches"
    }
    #if the user is typing into an object box
    if {$::new_object} {
        bind $::current_canvas <KeyRelease> {::completion::text_keys %K}
        if {![winfo exists .pop]} {
            ::completion::popup_draw
            ::completion::search $::current_text
            ::completion::try_common_prefix
            ::completion::update_completions_gui
            if {[::completion::unique] } {
                ::completion::choose_selected ;#Henri: was replace_text. This is needed for the three modes
                ::completion::popup_destroy
                ::completion::set_empty_listbox
            }
        } {
            if {[::completion::unique]} {
                ::completion::choose_selected
            } elseif { [llength $::completions] > 1 } {
                if {![::completion::try_common_prefix]} {
                    ::pdwindow::post "IF not common prefix\n"
                    #Henri: this would allow to cycle through the completions with Tab. I'm disabling that in favor of the arrow keys
                    #::completion::increment
                } else {
                    ::pdwindow::post "IF INDEED common prefix\n"
                }
            }
        }
    }
}

proc ::completion::monolithic_search {{text ""}} {
    #set variables related to monolithic_search
    ::completion::debug_msg "::completion::monolithic_search($text)" "searches"
    set ::current_search_mode 2
    if {[winfo exists .pop]} {
        .pop.f.lb configure -selectbackground $::completion::config(monobg)
    }
    #do the search
    set text [string range $text 1 end]
    set results {}
    ::completion::debug_msg "::completion::monolithic_search($text)" "searches"
    foreach elem $::monolithic_externals {
        #those are stored into a {libName objName} fashion
        set libraryName [lindex $elem 0]
        set objName [lindex $elem 1]
        ::completion::debug_msg "::completion::monolithic_search\[$libraryName\/$objName\]" "searches"
        lappend results "$libraryName\/$objName"
    }
    #::completion::debug_msg "----------results=\[$results"
    set pattern "$text"
    set ::completions [lsearch -all -inline -regexp -nocase $results $pattern]
}

proc ::completion::skipping_search {{text ""}} {
    #set variables related to skipping_search
    ::completion::debug_msg "::completion::skipping_search($text)" "searches"
    set ::current_search_mode 1
    if {[winfo exists .pop]} {
        .pop.f.lb configure -selectbackground $::completion::config(skipbg)
    }
    #do the search
    set text [string range $text 1 end]
    set chars [split $text {}]
    set pattern ""
    foreach char $chars {
        set pattern "$pattern$char.*"
    }
    ::completion::debug_msg "RegExp pattern  = $pattern" "searches"
    set ::completions [lsearch -all -inline -regexp -nocase $::all_externals $pattern]
    ::completion::debug_msg "--------------chars = $chars" "searches"
}

proc ::completion::search {{text ""}} {
    ::completion::debug_msg "::completion::search($text)" "searches"
    ::completion::debug_msg "::completion_text_updated = $::completion_text_updated" "searches"
    # without the arg there are some bugs when keys come from listbox ;# what Yvan meant?
    set ::erase_text $::current_text
    #if starts with a . it is a skipping search
    #if starts with a , it is a monolithic search
    if {[string range $text 0 0] eq ","} {
        ::completion::monolithic_search $text
        return
    } elseif {[string range $text 0 0] eq "."} {
        ::completion::skipping_search $text
        return
    }
    # Else just do the normal search
    if {[winfo exists .pop.f.lb]} {
        .pop.f.lb configure -selectbackground $::completion::config(bg)
    }
    set ::current_search_mode 0
    if {$text ne ""} {
        ::completion::debug_msg "=searching for $text=" "searches"
        set ::current_text $text
        set ::erase_text $text
        set ::should_restore False
    } elseif { !$::completion_text_updated } {
        ::completion::debug_msg "searching for empty string" "searches"
        #set ::current_text \
            [$::current_canvas itemcget $::current_tag -text]
        set ::previous_current_text $::current_text ;# saves the current text
        ::completion::debug_msg "original current_text: $::current_text" "searches"
        set ::current_text ""
        ::completion::debug_msg "replaced current_text is $::current_text" "searches"
        set ::should_restore True
    }
    ::completion::trimspaces

    # Now this part will always run so you can perform "empty searchs" which will return all objects. In Yvan's code it would clear completions on an "empty search"
    #Yvan was using -glob patterns but they wouldn't match stuff with forward slashes (/)
    #for example if you type "freq" it wouldn't match cyclone/freqshift~
    #using -regexp not allows for that
    #Also i've added case insensitive searching (since PD object creation IS case-insensitive).
    set pattern "$::current_text"
    if { $pattern eq "+"} {
        set pattern "\\+" ;# prevents an error when searching for "+"
    }
    set ::completions [lsearch -all -inline -regexp -nocase $::all_externals $pattern]
    if {$::should_restore} {
        set ::current_text $::previous_current_text ;# restores the current text
        ::completion::debug_msg "restored current_text: $::current_text" "searches"
    }
    ::completion::update_completions_gui
    ::completion::debug_msg "SEARCH END! Current text is $::current_text" "searches"
}

proc ::completion::update_completions_gui {} {
    ::completion::debug_msg "entering update_completions_gui" "entering_procs"
    if {[winfo exists .pop.f.lb]} {
        ::completion::scrollbar_check
        if {$::completions == {}} { ::completion::set_empty_listbox }
        if {[llength $::completions] > 1} {
            .pop.f.lb configure -state normal
            .pop.f.lb select clear 0 end
            .pop.f.lb select set 0 0
            .pop.f.lb yview scroll -100 page
        }
    }
}

proc ::completion::unique {} {
    ::completion::debug_msg "entering unique" "entering_procs"
    return [expr {[llength $::completions] == 1
                  && [::completion::valid]}]
}

proc ::completion::valid {} {
    ::completion::debug_msg "entering valid" "entering_procs"
    return [expr {[lindex $::completions 0] ne "(empty)"}]
}

# this is run when there are no results to display
proc ::completion::set_empty_listbox {} {
    ::completion::debug_msg "entering set_empty_listbox" "entering_procs"
    if {[winfo exists .pop.f.lb]} {
        ::completion::scrollbar_check
        .pop.f.lb configure -state disabled
    }
    set ::completions {"(empty)"}
}

#this proc moves the selection down (incrementing the index)
proc ::completion::increment {{amount 1}} {
    ::completion::debug_msg "entering increment" "entering_procs"
    ::completion::debug_msg "amount = $amount" "popup_gui"
    if {$::focus != "pop"} {
        focus .pop.f.lb
        set ::focus "pop"
    }
    # from now on it was on an "else"
    ::completion::debug_msg "bindtags = [bindtags .pop.f.lb]" "popup_gui"
    ::completion::debug_msg "bindings on .pop.f.lb = [bind .pop.f.lb]" "popup_gui"
    set selected [.pop.f.lb curselection]
    ::completion::debug_msg "selected = $selected" "popup_gui"
    
    #if completion list is empty then selected will be empty
    if { ![ string is integer -strict $selected] } {
        return
    }
    set updated [expr {($selected + $amount) % [llength $::completions]}]
    ::completion::debug_msg "updated = $updated" "popup_gui"
    .pop.f.lb selection clear 0 end
    .pop.f.lb selection set $updated
    ::completion::debug_msg "curselection after selection set = [.pop.f.lb curselection]" "popup_gui"
    .pop.f.lb see $updated
}

# store keywords (send/receive or array)
proc ::completion_store {tag} {
    # I'm disabling the unique names completion for now because i don't think it is desireable.
    # While it does detects when the user type a new name it **doesn't** when those names are not 
    # used any more (user closed their containing patch, deleted their objects, etc). 
    # In future versions we should be able to do that communicating with PD directly.
    return
    ::completion::debug_msg "entering completion store" "entering_procs"
    ::completion::debug_msg "   tag = $tag" "unique_names"
    set name 0
    set kind(sr) {s r send receive}
    set kind(sra) {send~ receive~}
    set kind(tc) {throw~ catch~}
    set kind(arr) {tabosc4~ tabplay~ tabread tabread4 \
                         tabread4~ tabread~ tabwrite tabwrite~}
    set kind(del) {delread~     delwrite~}

    if {[regexp {^(s|r|send|receive)\s(\S+)$} $tag -> do_not_matter name]} {
        set which sr
    }
    if {[regexp {^(send\~|receive\~)\s(\S+)$} $tag -> do_not_matter name]} {
        set which sra
    }
    if {[regexp {^(throw\~|catch\~)\s(\S+)$} $tag -> do_not_matter name]} {
        set which tc
    }
    if {[regexp {^tab\S+\s(\S+)$} $tag -> name]} {
        set which arr
    }
    if {[regexp {^(delread\~|delwrite\~)\s(\S+)\s*\S*$} $tag -> do_not_matter name]} {
        set which del
        ::completion::debug_msg "4 do_not_matter = $do_not_matter" "unique_names"
        ::completion::debug_msg "4 name = $name" "unique_names"
    }
    ::completion::debug_msg "Unique name = $name" "unique_names"
    if {$name != 0} {
        foreach key $kind($which) {
            ::completion::debug_msg "key = $key" "unique_names"
            if {[lsearch -all -inline -glob $::all_externals [list $key $name]] eq ""} {
                lappend ::all_externals [list $key $name]
                set ::all_externals [lsort $::all_externals]
            }
        }
    }
}

#this is called when the user selects the desired external
proc ::completion::choose_selected {} {
    ::completion::debug_msg "entering choose selected" "entering_procs"
    if {[::completion::valid]} {
        set selected_index [.pop.f.lb curselection]
        ::completion::popup_destroy
        set choosen_item [lindex $::completions $selected_index]
        #if we are on monolithic mode we should not write the "libName/"
        if {$::current_search_mode eq 2} {
            set libName [lindex [split $choosen_item /] 0]
            set choosen_item [lindex [split $choosen_item /] 1]
            # I'm addind this line just to have the option to print the lib name on the console but i don't think this is needed it apperas on the completions list.
            #::pdwindow::post "auto complete: [lindex [split $choosen_item /] 0] is part of the $libName library\n\n"
        }
        ::completion::replace_text $choosen_item
        ::completion::debug_msg "----------->Selected word: $choosen_item" "char_manipulation"
        set ::current_text "" ;# clear for next search
        ::completion::set_empty_listbox
        #focus -force $::current_canvas
        #set ::focus "canvas"
        ::completion::debug_msg "end of choose_selected current_text: $::current_text" "char_manipulation"
    }
}

# The keypressed and key released methods just route their input to this proc and it does the rest
proc ::completion::update_modifiers {key pressed_or_released} {
    switch -- $key {
        "Shift_L"   { set ::is_shift_down $pressed_or_released }
        "Shift_R"   { set ::is_shift_down $pressed_or_released }
        "Control_L" { set ::is_ctrl_down $pressed_or_released }
        "Control_R" { set ::is_ctrl_down $pressed_or_released }
        "Alt_L"     { set ::is_alt_down $pressed_or_released }
        "Alt_R"     { set ::is_alt_down $pressed_or_released }
    }
}

proc ::completion::key_presses {key} {
    ::completion::debug_msg "key pressed was $key\n" "key_event"
    ::completion::update_modifiers $key 1
    if {$::is_shift_down} {
        switch -- $key {
            "Up" {
                ::completion::increment -10 
            } 
            "Down" { 
                ::completion::increment 10
            }
        }        
    }
}

# receives KeyReleases pressed while listbox has focus
proc ::completion::lb_keys {key} {
    ::completion::debug_msg "~lb_keys~ key released was $key\n" "key_event"
    ::completion::update_modifiers $key 0
    set ::completion_text_updated 0
    #validate keys (currently we can't detect "~" in windows because it results in a "Multi_key")
    if {[regexp {^[a-zA-Z0-9~/\._\+\-]{1}$} $key]} {
        ::completion::insert_key $key; return
    }
    switch -- $key {
        "space"     { ::completion::insert_key " " } ;# search
        "Return"    { ::completion::choose_selected }
        "BackSpace" { ::completion::chop } ;# search
        "comma" { ::completion::insert_key "," } ;# search
        "period" { ::completion::insert_key "." } ;# search
        "plus" { ::completion::insert_key "+" }
        "minus" { ::completion::insert_key "-" }
        "underscore" { ::completion::insert_key "_" }
    }

}

# keys from textbox
proc ::completion::text_keys {key} {
    ::completion::debug_msg "~text_keys~ key pressed was $key\n" "key_event"
    set ::completion_text_updated 0
    switch -- $key {
        "plus"   { set key "+" }
        "minus"   { set key "-" }
        "Escape" { ::completion::popup_destroy 1 }
    }
    if {[regexp {^[a-zA-Z0-9~/\._\+\-\*]{1}$} $key]} {
        ::completion::search
    } elseif {$key eq "space"} {
        ::completion::search
    } elseif {$key eq "BackSpace"} {
        after 10; ::completion::search ;# FIXME
    } elseif {$key eq "Return"} {
        ::completion::choose_or_unedit
    }
}

# this inserts the key
proc ::completion::insert_key {key} {
    scan $key %c keynum
    # pdsend "pd key 1 $keynum 0" ; notworking
    ::completion::sendKeyDown $keynum
    ::completion::debug_msg "inserting key $keynum" "char_manipulation"
    append ::current_text $key
    # to debug the right line
    ::completion::search $::current_text
    set ::focus "canvas"
    pdtk_text_editing $::toplevel $::current_tag 1
    set ::completion_text_updated 0    
    # for some reason this does not work without passing the arg ;# what Yvan meant?
    #Those lines were making the completion windom vanish!
    #focus -force $::toplevel 
    #focus -force $::current_canvas
}

# erases what the user typed since it started the pluging
proc ::completion::erase_text {} {
    ::completion::debug_msg "entering erase text" "entering_procs"
    # simulate backspace keys
    ::completion::debug_msg "erase_text = $::erase_text" "char_manipulation"
    set i [expr {[string length $::erase_text] + 2}] ;# FIXME
    while {--$i > 0} {
        ::completion::sendKeyDownAndUp 8 ;#8 = BackSpace
        incr i -1
    }
}

# this is the proc that types the object name for the user. It runs in two steps
# 1: by erasing what the user typed (calling erase_text)
# 2: typing the match chosen by the user
# Why not just send the remaining chars? It would not make sense in "skip" search mode!
# You might also wonder why not use
#       pdtk_text_selectall $::current_canvas $::current_tag
#                               OR
#       pdtk_text_set $::current_canvas $::current_tag ""
# to select everything and delete it or directly clear the text object. 
# I've tried it but it doesn't work (idky yet).
proc ::completion::replace_text {args} {
    ::completion::debug_msg "===Entering replace_text" "entering_procs"
    set text ""
    ::completion::erase_text
    if { !$::completion::config(auto_complete_libs) || ($::completion::config(auto_complete_libs) && $::is_shift_down) } {
        set args [split $args /]
        set args [lindex $args end]
    }
    # if there are soaces the args variable will arrive as a list. Example: {list append} ;# Henri: what are soaces??
    # this foreach concatenates it back to a string. Example: list append
    foreach arg $args { set text [concat $text $arg] }
    #for each char send a keydown event to PD to simulate user key presses
    for {set i 0} {$i < [string length $text]} {incr i 1} {
        set cha [string index $text $i]
        # ::completion::debug_msg "current char =  $cha"
        scan $cha %c keynum
        ::completion::sendKeyDown $keynum
    }
    set ::erase_text $text
        ::completion::debug_msg "erase_text = $::erase_text" "char_manipulation"
    # nasty hack: the widget does not update his text because we pretend
    # we typed the text although we faked it so pd gets it as well (mmh)
    set ::completion_text_updated 1
    #set ::current_text "" ; Not needed because choose_selected will empty that
}

# called when user press Enter
proc ::completion::choose_or_unedit {} {
    ::completion::debug_msg "entering choose or unedit" "entering_procs"
    if {[winfo exists .pop] && [::completion::valid]} {
        ::completion::choose_selected
    } {
        ::completion::text_unedit
    }
}

proc ::completion::text_unedit {} {
    ::completion::debug_msg "entering text unedit" "entering_procs"
    pdsend "$::focused_window reselect"
    set ::new_object 0
    set ::completion_text_updated 0
}

# this is called when the user press the BackSpace key (erases on char)
proc ::completion::chop {} {
    ::completion::debug_msg "entering chop" "entering_procs"
    #if the user press shift+backspace restart search
    if {$::is_shift_down} {
        ::completion::debug_msg "shift+BackSpace = clearing search" "char_manipulation"
        ::completion::erase_text
        set ::current_text ""
        ::completion::search
        return
    }
    ::completion::sendKeyDownAndUp 8 ;#8 = BackSpace
    #::completion::debug_msg "current_text before chopping $::current_text"
    set ::current_text [string replace $::current_text end end] ;#this removes the last char (?!)
    ::completion::debug_msg "current_text after choping = $::current_text" "char_manipulation"
    #::completion::debug_msg "current_text after chopping $::current_text"
    ::completion::search $::current_text
    #what does it do?
    if {[winfo exists .pop]} {
        .pop.f.lb selection clear 0 end
        .pop.f.lb selection set 0
    }
    # focus -force $::current_canvas ;# THIS IS THE LINE THAT MAKES THE AUTOCOMPLETE VANISH AFTER BACKSPACE
    set ::focus "canvas"
}

proc ::completion::popup_draw {} {
    ::completion::debug_msg "entering popup draw" "entering_procs"
    if {![winfo exists .pop]} {
        set screen_w [winfo screenwidth $::current_canvas]
        set screen_h [winfo screenheight $::current_canvas]
        ::completion::debug_msg "Screen width = $screen_w" "popup_gui"
        #::completion::debug_msg "Screen height = $screen_h"
        set popup_width 40
        set menuheight 32
        if {$::windowingsystem ne "aqua"} { incr menuheight 24 }
        incr menuheight $::completion::config(offset)
        set geom [wm geometry $::toplevel]
        # fix weird bug on osx
        set decoLeft 0
        set decoTop 0
        regexp -- {([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)} $geom -> \
            width height decoLeft decoTop
        set left [expr {$decoLeft + $::editx}]
        set top [expr {$decoTop + $::edity + $menuheight}]
        ::completion::debug_msg "left = $left" "popup_gui"
        ::completion::debug_msg "top = $top" "popup_gui"
        catch { destroy .pop }
        toplevel .pop
        wm overrideredirect .pop 1 
        if {$::windowingsystem eq "aqua"} {            
            raise .pop ;# without this the gui would NOT be displayed on OS X
        }
        wm geometry .pop +$left+$top
        frame .pop.f -takefocus 0

        pack configure .pop.f
        .pop.f configure -relief solid -borderwidth 1 -background white

        #is this needed?
        switch -- $::current_search_mode {
            0 { set currentbackground $::completion::config(bg) }
            1 { set currentbackground $::completion::config(skipbg) }
            2 { set currentbackground $::completion::config(monobg) }
        }
        
        listbox .pop.f.lb \
            -selectmode browse \
            -width $popup_width \
            -height $::completion::config(max_lines) \
            -listvariable ::completions -activestyle none \
            -highlightcolor $::completion::config(fg) \
            -selectbackground $currentbackground \
            -selectforeground $::completion::config(fg) \
            -yscrollcommand [list .pop.f.sb set] -takefocus 1 \
            -disabledforeground #333333

        pack .pop.f.lb -side left -expand 1 -fill both
        .pop.f.lb configure -relief flat \
            -font [list $::completion::config(font) $::completion::config(font_size)] \
            -state normal

        pack .pop.f.lb [scrollbar ".pop.f.sb" -command [list .pop.f.lb yview] -takefocus 0] \
            -side left -fill y -anchor w
        bind .pop.f.lb <Escape> {after idle { ::completion::popup_destroy 1 }}
        bind .pop.f.lb <KeyRelease> {::completion::lb_keys %K}
        bind .pop.f.lb <Key> {after idle {::completion::key_presses %K}}
        bind .pop.f.lb <ButtonRelease> {after idle {::completion::choose_selected}}

        # Overriding the Up and Down key due to a bug:
        # the .pop.f.lb selection set $updated call in ::completion::increment 
        # works but on the next non-overridden Up/Down event it would resume from the last 
        # index BEFORE the ::increment call. It would happend because of the event being dispatch 
        # to the next bindtag which would be ListBox.

        # for that reason  we could remove the ListBox bindtag. It would also avoids strange behaviour with home and end keys (that for some reason can't be overriden)
        # yet if we do this the user wouldn't be able to select the suggestions with the mouse so we leave the ListBox on the bindtags.
        #bindtags .pop.f.lb {.pop.f.lb .pop all} 

        # and then set my own bindings (Those Up and Down binds would override the Up and Down on the ListBox bindtags if they weren't removed)
        bind .pop.f.lb <Up> {::completion::increment -1 ; break}
        bind .pop.f.lb <Down> {::completion::increment 1 ; break}
        bind .pop.f.lb <Shift-Up> {after idle {::completion::increment -10} ; break}
        bind .pop.f.lb <Shift-Down> {after idle {::completion::increment 10} ; break}

        # I could NOT override the Next and Prior keys (Pg Up and Pg Down) without removing the ListBox bindtag. Strange hmmm probably a bug
        # also even after removing the ListBox from the bindtags those don't work! Only if i hold some modifier (so it becomes more specific).
        # probably part of the same bug
        bind .pop.f.lb <Prior> {after idle {::completion::increment -20} ; break}
        bind .pop.f.lb <Next> {after idle {::completion::increment 20} ; break}

        # bindings for Home and End
        bind .pop.f.lb <Home> {after idle {
            .pop.f.lb selection clear 0 end
            .pop.f.lb selection set 0
            .pop.f.lb see 0
            } ; break}
        bind .pop.f.lb <End> {after idle {
            .pop.f.lb selection clear 0 end
            .pop.f.lb selection set end
            .pop.f.lb see end
            } ; break}
        focus .pop.f.lb
        set ::focus "pop"
        .pop.f.lb selection set 0 0
        ::completion::debug_msg "top = $top" "popup_gui"
        set height [winfo reqheight .pop.f.lb]
        # if the popup windows were going to be displayed partly off-screen let's move it left so it doesn't
        #the width is given in units of 8 pixels
        #https://core.tcl.tk/bwidget/doc/bwidget/BWman/ListBox.html#-width
        if { [expr {$left+$popup_width*8>$screen_w}] } {
            set left [expr {$screen_w-$popup_width*8} ]
            ::completion::debug_msg "left = $left" "popup_gui"
        }
        if {$::windowingsystem eq "win32"} {
            # here we assume the user did not set the taskbark  on the sides and also did not set it's size to be more than 1/7 of the screen
            incr screen_h [ expr {-1*$screen_h/7} ]
        }
        #winfo height window
        #Returns a decimal string giving window's height in pixels. When a window is first created its height will be 1 pixel; the height will eventually be changed by a geometry manager to fulfil the window's needs. If you need the true height immediately after creating a widget, invoke update to force the geometry manager to arrange it, or use winfo reqheight to get the window's requested height instead of its actual height.
        ::completion::debug_msg "@screen_h = $screen_h\n        @height = $height" "popup_gui"
        if { [expr {$top+$height>$screen_h}] } {
            set top [expr {$screen_h-$height} ]
            wm geometry .pop +$left+$top
            #.pop.f.lb configure -+
            ::completion::debug_msg "top = $top" "popup_gui"
        }
    }
}

proc ::completion::popup_destroy {{unbind 0}} {
    ::completion::debug_msg "entering popup_destroy" "entering_procs"
    catch { destroy .pop }
    focus -force $::current_canvas
    set ::focus "canvas"
    if {$unbind} {
        bind $::current_canvas <KeyRelease> {}
    }
    set ::current_text ""
}

# Henri: i don't get exactly what this does. Commenting out those packs seems to have absolutely no effect in my system
# pack documentation: https://www.tcl.tk/man/tcl/TkCmd/pack.htm#M11
proc ::completion::scrollbar_check {} {
    ::completion::debug_msg "entering scrollbar_check" "entering_procs"
    if {[winfo exists .pop]} {
        if {[llength $::completions] < $::completion::config(max_lines)} {
            #::completion::debug_msg "completions < max numer of lines"
            pack forget .pop.f.sb
        } else {
            #::completion::debug_msg "completions >= max numer of lines"
            pack .pop.f.sb -side left -fill y
        }
    }
}

###########################################################
#                      overwritten                        #
###########################################################
proc pdtk_text_editing {mytoplevel tag editing} {
    ::completion::debug_msg "entering overwritten pdtk text editing" "entering_procs"
    #::completion::debug_msg "   mytoplevel = $mytoplevel"
    #::completion::debug_msg "   tag = $tag"
    #::completion::debug_msg "   editing = $editing"
    set ::toplevel $mytoplevel
    set tkcanvas [tkcanvas_name $mytoplevel]
    set rectcoords [$tkcanvas bbox $tag]
    if {$rectcoords ne ""} {
        set ::editx  [expr {int([lindex $rectcoords 0])}]
        set ::edity  [expr {int([lindex $rectcoords 3])}]
    }
    if {$editing == 0} {
        selection clear $tkcanvas
        # completion
        # Henri: Yvan originally called set_empty_listbox. Doens't seem to make sense. It wouldn't even reset ::current_text
        ::completion::popup_destroy
        set ::completion_text_updated 0
        # store keywords. Henri: i'm disabling that. See developmentGuide.md
        #if {$::completion::config(save_mode)} {
        #    set text [$tkcanvas itemcget $::current_tag -text]
        #    ::completion_store $text
        #}
    } {
        set ::editingtext($mytoplevel) $editing
        # completion
        set ::current_canvas $tkcanvas
        if {$tag ne ""} {
            # unbind Keys if new object
            if {$tag ne $::current_tag} {
                bind $::current_canvas <KeyRelease> {}
            }
            set ::current_tag $tag
        }
    }
    set ::new_object $editing
    $tkcanvas focus $tag
    set ::focus "tag"
}


############################################################
# utils

# `prefix' from Bruce Hartweg <http://wiki.tcl.tk/44>
proc ::completion::prefix {s1 s2} {
    regexp {^(.*).*\0\1} "$s1\0$s2" all pref
    return $pref
}

proc ::completion::try_common_prefix {} {
    set found 0
    set prefix [::completion::common_prefix]
    if {$prefix ne $::current_text && $prefix ne ""} {
        ::completion::replace_text $prefix
        # prevent errors in pdtk_text_editing
        catch { focus .pop.f.lb }
        set ::current_text $prefix
        set found 1
    }
    return $found
}

proc ::completion::common_prefix {} {
    set prefix ""
    if {[llength $::completions] > 1} {
        set prefix [::completion::prefix \
                        [lindex $::completions 0] \
                        [lindex $::completions end]]
    }
    return $prefix
}

proc ::completion::trimspaces {} {
    set ::current_text [string trimright $::current_text " "]
}


proc ::completion::debug_button {} {
    ::completion::debug_msg "CLICKED OKAY"
}

# just in case.
bind all <$::modifier-Key-Return> {pdsend "$::focused_window reselect"}

###########################################################
# main

::completion::init
