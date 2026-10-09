# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


# ==========================================

# Copyright (c) 2011-2023 yvan, henri, porres
# The original version was developed by Yvan Volochine in 2011.
# Henri Augusto embraced in 2018. Porres took over in 2023
#
# https://github.com/porres/completion-plugin

package require Tcl 8.5
package require pd_menucommands 0.1

namespace eval ::dialog_path:: {
    variable use_standard_paths_button 1
    variable verbose_button 0
    variable docspath ""
    variable installpath ""
    namespace export pdtk_path_dialog
}

namespace eval ::completion:: {
    variable ::completion::config
}

###########################################################
# overwritten
rename pdtk_text_editing pdtk_text_editing_old

############################################################
# GLOBALS

set ::completion::plugin_version "0.50.0-pd056"

# default
set ::completion::config(max_lines) 15
set ::completion::config(n_lines) $::completion::config(max_lines)
if {$::windowingsystem eq "aqua"} {
    set ::completion::config(font) "Menlo"
} else {
    set ::completion::config(font) "DejaVu Sans Mono"
}
set ::completion::config(font_size) 12
set ::completion::config(font_weight) "normal"
set ::completion::config(bg) blue
set ::completion::config(auto_complete_libs) 0

# private variables

set ::completion::plugin_path ""
set ::completion::toplevel ""
set ::completion::current_canvas ""
set ::completion::current_tag ""
set ::completion::current_text ""
set ::completion::erase_text ""
set ::completion::completions {"(empty)"}
set ::completion::new_object false
set ::completion::editx 0
set ::completion::edity 0
set ::completion::focus ""
set ::completion::completion_text_updated 0
set ::completion::is_shift_down 0
set ::completion::is_ctrl_down 0
set ::completion::is_alt_down 0
set ::completion::waiting_trigger_keyrelease 0

# =========== [DEBUG mode on/off] ============
# 1 = true 0 = false
set ::completion::completion_debug 0
# debug categories
set ::completion::debug_loaded_externals 0
set ::completion::debug_entering_procs 1
set ::completion::debug_key_event 1
set ::completion::debug_searches 1
set ::completion::debug_popup_gui 1
set ::completion::debug_char_manipulation 1
set ::completion::debug_settings 1
set ::completion::debug_prefix 0

# (0 = normal / 1 = skipping)
set ::completion::current_search_mode 0

set ::completion::all_externals {}
set ::completion::loaded_paths {}

#useful function for debugging
proc ::completion::msg_debug {dbgMsg {debugKey "none"}} {
    switch -- $debugKey {
        "none" {}
        "loaded_externals" { if { !$::completion::debug_loaded_externals } { return  } }
        "entering_procs" { if { !$::completion::debug_entering_procs } { return  } }
        "key_event" { if { !$::completion::debug_key_event } { return  } }
        "searches" { if { !$::completion::debug_searches } { return  } }
        "popup_gui" { if { !$::completion::debug_popup_gui } { return  } }
        "char_manipulation" { if { !$::completion::debug_char_manipulation } { return  } }
        "settings" { if { !$::completion::debug_settings } { return  } }
    }
    if { $::::completion::completion_debug } {
        ::pdwindow::post "autocmpl_dbg: $dbgMsg\n"
    }
}

# This function sends keydown messages to pd
proc ::completion::sendKeyDown {keynum} {
    pdsend "[winfo toplevel $::completion::current_canvas] key 1 $keynum 0"
}

# This function sends keydown and then keyup messages to pd
proc ::completion::sendKeyDownAndUp {keynum} {
    pdsend "[winfo toplevel $::completion::current_canvas] key 1 $keynum 0"
    pdsend "[winfo toplevel $::completion::current_canvas] key 0 $keynum 0"
}

# ============================================================
# === FIX 1: menu initialization for Pd 0.56 ===
# In Pd 0.56 the Preferences menu is created as ".preferences"
# and is NOT nested under ".menubar.apple". The old hardcoded
# path caused an "invalid command name" error at load time.
# ============================================================
proc ::completion::init_options_menu {} {
    if {[winfo exists .preferences]} {
        .preferences add separator
        .preferences add command \
            -label [_ "Completion-plugin"] \
            -command {::completion::show_options_gui}
    } else {
        ::pdwindow::post "completion-plugin: WARNING - .preferences menu not found; skipping menu entry.\n"
    }
}

#called once upon plugin initialization
proc ::completion::init {} {
    set ::completion::plugin_path "$::current_plugin_loadpath"
    ::pdwindow::post "------------- completion-plugin -------------\n"
    ::pdwindow::post "Version: $::completion::plugin_version\n"

    ::completion::read_config

    if {![info exists ::completion::config(hotkey)] || $::completion::config(hotkey) eq ""} {
        set ::completion::config(hotkey) "F12"
    }
    ::pdwindow::post "completion-plugin: trigger key is <$::completion::config(hotkey)>\n"

    # Append our handler to Pd's existing <KeyPress> binding on "all".
    # Avoid the "+" syntax because some Tcl builds reject "+{...}".
    set old_binding [bind all <KeyPress>]
    ::pdwindow::post "completion-plugin: existing 'all' KeyPress binding = '$old_binding'\n"
    if {$old_binding eq ""} {
        bind all <KeyPress> {::completion::all_key_handler %K}
    } else {
        bind all <KeyPress> "${old_binding}\n::completion::all_key_handler %K"
    }

    ::completion::scan_all_completions
    ::completion::init_options_menu
}

proc ::completion::scan_all_completions {} {
    set initTime [clock milliseconds]

    set ::completion::all_externals {
        bang trigger route swap print float int value symbol makefilename send receive \
        pack unpack list append list\ prepend list\ store list\ split list\ trim list\ length list\ fromsymbol list\ tosymbol \
        tabread tabread4 tabwrite soundfiler table array\ define array\ size array\ sum array\ get array\ set array\ quantile array\ random array\ max array\ min \
        qlist textfile text\ define text\ get text\ set text\ insert text\ delete text\ size text\ tolist text\ fromlist text\ search text\ sequence \
        file\ handle file\ define file\ mkdir file\ which file\ glob file\ stat file\ isdirectory file\ isfile file\ size file\ copy file\ move file\ delete file\ split file\ splitex file\ join file\ splitname \
        delay pipe metro line timer cputime realtime \
        select change spigot moses until \
        expr clip random + - * / max min > >= < <= == != div mod && || & | << >> sin cos tan atan atan2 wrap abs sqrt exp log pow \
        mtof ftom rmstodb dbtorms powtodb dbtopow \
        midiin midiout notein noteout ctlin ctlout pgmin pgmout bendin bendout touchin touchout polytouchin polytouchout sysexin midirealtimein makenote stripnote poly oscparse oscformat \
        openpanel savepanel key keyup keyname netsend netreceive fudiparse fudiformat bag trace \
        adc~ dac~ sig~ line~ vline~ threshold~ env~ snapshot~ vsnapsot~ bang~ samphold~ samplerate~ send~ receive~ throw~ catch~ readsf~ writesf~ print~ \
        fft~ ifft~ rfft~ irfft~ expr~ fexpr~ +~ -~ *~ /~ max~ min~ clip~ sqrt~ rsqrt~ wrap~ pow~ exp~ log~ abs~ \
        mtof~ ftom~ rmstodb~ dbtorms~ powtodb~ dbtopow~ \
        noise~ phasor~ cos~ osc~ tabosc4~ tabplay~ tabwrite~ tabread~ tabread4~ tabsend~ tabreceive~ \
        vcf~ hip~ lop~ slop~ bp~ biquad~ rpole~ rzero~ rzero_rev~ cpole~ czero~ czero_rev~ \
        delwrite~ delread~ delread4~ \
        loadbang declare savestate clone pdcontrol pd inlet inlet~ outlet outlet~ namecanvas block~ switch~ \
        struct drawpolygon filledpolygon drawcurve filledcurve drawnumber drawsymbol drawtext plot scalar pointer get set element getsize setsize append \
        sigmund~ bonk~ choice hilbert~ complex-mod~ loop~ lrshift~ pd~ stdout rev1~ rev2~ rev3~ bob~ output~
    }
    ::completion::add_user_externals
    ::completion::add_user_customcompletions

    set ::completion::loaded_paths {}

    set ::completion::all_externals [lsort -unique $::completion::all_externals]

    set count [llength $::completion::all_externals]
    ::pdwindow::post "found $count suggestions\n"
    ::pdwindow::post "\n"
    ::pdwindow::post "------------- completion-plugin -------------\n"
}

#opens the plugin's manual file (as called from the configuration window)
proc ::completion::open_manual_file {} {
    set filename [file join $::completion::plugin_path "manual.pd"]
    open_file "$filename"
}

proc ::completion::show_options_gui {} {
    if {[winfo exists .options]} {
        focus .options
        return
    }
    toplevel .options
    wm title .options "Completion Plugin Settings"

    frame .options.f -padx 5 -pady 5

    label .options.f.click_to_choose_label -text "click to\nchoose"

    label .options.f.hotkeylabel -text "hotkey (requires restart)"
    entry .options.f.hotkeyentry -width 12
    .options.f.hotkeyentry insert 0 "$::completion::config(hotkey)"
    bind .options.f.hotkeyentry <KeyRelease> {
        set ::completion::config(hotkey) [.options.f.hotkeyentry get]
    }

    button .options.f.save_btn -text "Save settings" -command ::completion::write_config
    button .options.f.default_btn -text "Restore factory settings" -command ::completion::restore_default_option
    button .options.f.rescan_btn -text "Rescan externals" -command ::completion::scan_all_completions
    .options.f.rescan_btn configure -font {-weight bold}
    button .options.f.manual_btn -text "Open Manual" -command ::completion::open_manual_file
    .options.f.manual_btn configure -font {-weight bold}

    set padding 2

    grid .options.f -column 0 -row 0

    set current_row 1

    grid .options.f.hotkeylabel -column 0 -row $current_row -padx $padding -pady $padding
    grid .options.f.hotkeyentry -column 1 -row $current_row -padx $padding -pady $padding
    incr current_row

    grid .options.f.default_btn -column 0 -row $current_row -padx $padding -pady 8 -sticky "e"
    grid .options.f.save_btn -column 1 -row $current_row -padx $padding -pady 8 -sticky "w"
    incr current_row
    grid .options.f.rescan_btn -column 0 -row $current_row -padx $padding -pady 4 -sticky "ew"
    grid .options.f.manual_btn -column 1 -row $current_row -padx $padding -pady 8 -sticky "w"

    ::completion::update_options_gui
}

proc ::completion::update_options_gui {} {
    .options.f.hotkeyentry delete 0 end
    .options.f.hotkeyentry insert 0 $::completion::config(hotkey)
}

proc ::completion::restore_default_option {} {
    set ::completion::config(hotkey) "Alt_L"
    if {$::windowingsystem eq "aqua"} {
        set ::completion::config(font) "Menlo"
    } else {
        set ::completion::config(font) "DejaVu Sans Mono"
    }
    ::completion::update_options_gui
    ::completion::write_config
}

proc ::completion::gui_options_update_color {entryWidget frameWidget configTag} {
    if { [regexp {^\#(\d|[a-f]){6}$} [$entryWidget get]] } {
        set ::completion::config($configTag) [$entryWidget get]
        $frameWidget configure -background $::completion::config($configTag)
        $entryWidget configure -foreground #000000
    } else {
        $entryWidget configure -foreground #de2233
    }
}

proc ::completion::read_config {{filename completion.cfg}} {
    if {[file exists $filename]} {
        set fp [open $filename r]
    } else {
        set filename [file join $::completion::plugin_path $filename]
        if {[file exists $filename]} {
            set fp [open $filename r]
        } else {
            ::completion::msg_debug "completion.cfg not found"
            return False
        }
    }
    while {![eof $fp]} {
        set data [gets $fp]
        if { ![regexp {^\w} $data] } {
            continue
        }
        if { [llength $data ] == 2} {
            set ::completion::config([lindex $data 0]) [lindex $data 1]
        } elseif { [llength $data ] > 2} {
            set ::completion::config([lindex $data 0]) [lrange $data 1 end]
        }
    }
    close $fp
    return True
}

proc ::completion::write_config {{filename completion.cfg}} {
    if { [file exists $filename] } {
        set fp [open $filename r]
        set had_to_create_file false
    } else {
        set filename [file join $::completion::plugin_path $filename]
        if {[file exists $filename]} {
            set fp [open $filename r]
            set had_to_create_file false
        } else {
            set fp [open $filename w+]
            set had_to_create_file true
        }
    }
    set lines [split [read $fp] "\n"]
    close $fp

    set lines [::completion::write_config_variable $lines "hotkey"]

    set fp [open $filename w]
    if { $had_to_create_file } {
        set lines [linsert $lines 0 "This file was generated by Completion Plugin in the absence of the original file that comes with the plugin.\n"]
    }
    puts $fp [join $lines "\n"]
    close $fp
}

proc ::completion::write_config_variable {file_lines name} {
    set pattern ^$name\\s
    set index 0
    set found false
    foreach line $file_lines {
        if {[regexp $pattern $line]} {
            set file_lines [lreplace $file_lines $index $index "$name $::completion::config($name)"]
            set found true
        }
        incr index
    }
    if { !$found } {
        lappend file_lines "$name $::completion::config($name)"
    }
    return $file_lines
}

proc ::completion::add_user_externalsOnFolder {{dir .} depth} {
    set pd_files [glob -directory $dir -nocomplain -types {f} -- *.pd]
    foreach filepath $pd_files {
        set file_tail [file tail $filepath]
        set name_without_extension [file rootname $file_tail]
        set how_many_folders_to_get $depth
        set folder_name [lrange [file split $filepath] end-$how_many_folders_to_get end-1 ]
        set extension_path [join $folder_name \/]
        if {$extension_path ne ""} {
            set extension_path $extension_path\/
        }
        # Strip -help suffix if present, otherwise use name as-is.
        if {[string range $name_without_extension end-4 end] eq "-help"} {
            set external_name [string range $name_without_extension 0 end-5]
        } else {
            set external_name $name_without_extension
        }
        lappend ::completion::all_externals $extension_path$external_name
    }
}

proc ::completion::search_static_temp {} {
    set pathlist [concat $::sys_staticpath $::sys_temppath]
    foreach pathdir $pathlist {
        set dir [file normalize $pathdir]
        if { ! [file isdirectory $dir]} {
            continue
        }
        lappend ::completion::loaded_paths $pathdir
        ::completion::add_user_externalsOnFolder $dir 0
        foreach subdir [glob -nocomplain -directory $dir -type d *] {
            set folder_name [lrange [file split $pathdir] end end ]
            if { $folder_name eq "extra" } {
                set subdir_name [lrange [file split $subdir] end end ]
                if { $subdir eq "bob~" } {
                    return
                } elseif { $subdir_name eq "bonk~" } {
                    return
                } elseif { $subdir_name eq "choice" } {
                    return
                } elseif { $subdir_name eq "fiddle~" } {
                    return
                } elseif { $subdir_name eq "loop~" } {
                    return
                } elseif { $subdir_name eq "lrshift~" } {
                    return
                } elseif { $subdir_name eq "pd~" } {
                    return
                } elseif { $subdir_name eq "pique" } {
                    return
                } elseif { $subdir_name eq "sigmund~" } {
                    return
                } elseif { $subdir_name eq "stdout" } {
                    return
                } else {
                    lappend ::completion::loaded_paths $subdir
                    ::completion::add_user_externalsOnFolder $subdir 1
                }
            } else {
                lappend ::completion::loaded_paths $subdir
                ::completion::add_user_externalsOnFolder $subdir 1
            }
        }
    }
}

proc ::completion::add_user_externals {} {
    if {[namespace exists ::pd_docsdir] && [::pd_docsdir::externals_path_is_valid]} {
        set path [::pd_docsdir::get_externals_path]
        lappend ::completion::loaded_paths $path
        set dir [file normalize $path]
        ::completion::add_user_externalsOnFolder $dir 0
        foreach subdir [glob -nocomplain -directory $dir -type d *] {
            lappend ::completion::loaded_paths $subdir
            ::completion::add_user_externalsOnFolder $subdir 1
        }
    }
    ::completion::search_static_temp
    set searchpaths [concat $::sys_searchpath]
    set ::completion::loaded_paths [lsort -unique $::completion::loaded_paths]
    foreach searchpath $searchpaths {
        set dir [file normalize $searchpath]
        set done_before 0
        foreach paths $::completion::loaded_paths {
            if { $dir eq $paths } {
                set done_before 1
                break
            }
        }
        if { ! $done_before } {
            ::completion::add_user_externalsOnFolder $dir 0
            lappend ::completion::loaded_paths $dir
            foreach subdir [glob -nocomplain -directory $dir -type d *] {
                lappend ::completion::loaded_paths $subdir
                ::completion::add_user_externalsOnFolder $subdir 1
            }
        }
    }
}

proc ::completion::add_user_customcompletions {} {
    set userdir [file join $::completion::plugin_path "custom_completions"]
    foreach filename [glob -directory $userdir -nocomplain -types {f} -- *.txt] {
        ::completion::read_completionslist_file $filename
    }
}

proc ::completion::read_completionslist_file {afile} {
    if {[file exists $afile]
        && [file readable $afile]
    } {
        set fl [open $afile r]
        while {[gets $fl line] >= 0} {
            if {[string index $line 0] ne ";"
                && [string index $line 0] ne " "
                && [string index $line 0] ne ""
                && [lsearch -exact $::completion::all_externals $line] == -1} {
                lappend ::completion::all_externals $line
            }
        }
        close $fl
    }
}

###########################################################
#                      overwritten                        #
###########################################################
proc pdtk_text_editing {mytoplevel tag editing} {
    ::completion::msg_debug "pdtk_text_editing: toplevel=$mytoplevel tag=$tag editing=$editing" "key_event"
    set ::completion::toplevel $mytoplevel
    set tkcanvas [tkcanvas_name $mytoplevel]
    set rectcoords [$tkcanvas bbox $tag]
    if {$rectcoords ne ""} {
        set ::completion::editx  [expr {int([lindex $rectcoords 0])}]
        set ::completion::edity  [expr {int([lindex $rectcoords 3])}]
    }
    if {$editing == 0} {
        selection clear $tkcanvas
        ::completion::popup_destroy
        set ::completion::completion_text_updated 0
    } else {
        set ::editingtext($mytoplevel) $editing
        set ::completion::current_canvas $tkcanvas
        if {$tag ne ""} {
            set ::completion::current_tag $tag
        }
    }
    set ::completion::new_object $editing
    $tkcanvas focus $tag
    set ::completion::focus "canvas"
}

# Central key handler bound directly on the canvas widget.
# We do NOT add custom bindtags, to avoid interfering with Pd 0.56's
# own text input handling.

# Global key handler installed on the "all" bindtag.
# Filters aggressively so it only acts when a completion popup is relevant.
proc ::completion::all_key_handler {key} {
    # Only act when an object box is being edited.
    if {!$::completion::new_object} { return }
    if {$::completion::current_canvas eq "" || $::completion::current_tag eq ""} { return }

    # Hotkey: open the popup and consume the key so it doesn't get typed.
    if {$key eq $::completion::config(hotkey)} {
        ::completion::msg_debug "hotkey pressed: $key" "key_event"
        ::completion::trigger
        return -code break
    }

    # If the popup is open, handle navigation / selection.
    if {[winfo exists .pop]} {
        switch -- $key {
            "Return"    { ::completion::choose_selected ; return -code break }
            "Escape"    { ::completion::popup_destroy 1 ; return -code break }
        }
    }
    # Everything else falls through to Pd's own handling.
}

proc ::completion::trigger {} {
    ::completion::msg_debug "===trigger fired===" "entering_procs"

    if {$::completion::current_canvas eq "" || $::completion::current_tag eq ""} {
        ::completion::msg_debug "trigger: no canvas/tag, aborting" "key_event"
        return
    }

    set font_info [$::completion::current_canvas itemcget $::completion::current_tag -font]
    set ::completion::config(font)         [lindex $font_info 0]
    set size [lindex $font_info 1]
    set ::completion::config(font_size)    [expr {$size ne "" ? $size * -1 : 12}]
    set ::completion::config(font_weight)  [lindex $font_info 2]

    set ::completion::current_text [$::completion::current_canvas itemcget $::completion::current_tag -text]
    ::completion::trimspaces
    ::completion::msg_debug "trigger: current text = '$::completion::current_text'" "searches"

    ::completion::search $::completion::current_text

    set listsize [llength $::completion::completions]
    if {$listsize < $::completion::config(max_lines)} {
        set ::completion::config(n_lines) $listsize
    } else {
        set ::completion::config(n_lines) $::completion::config(max_lines)
    }

    if {![winfo exists .pop]} {
        ::completion::popup_draw
    } else {
        ::completion::update_completions_gui
    }

    if {[llength $::completion::completions] == 0} {
        ::completion::set_empty_listbox
        ::completion::msg_debug "trigger: no completions found" "searches"
    } else {
        ::completion::msg_debug "trigger: [llength $::completion::completions] completions found" "searches"
    }
}

proc ::completion::skipping_search {{text ""}} {
    ::completion::msg_debug "::completion::skipping_search($text)" "searches"
    set ::completion::current_search_mode 1
    if {[winfo exists .pop]} {
        .pop.f.lb configure -selectbackground $::completion::config(bg)
    }
    set text [string range $text 1 end]
    set text [::completion::fix_pattern $text]
    set chars [split $text {}]
    set pattern ""
    foreach char $chars {
        set pattern "$pattern$char.*"
    }
    set ::completion::completions [lsearch -all -inline -regexp -nocase $::completion::all_externals $pattern]
}

proc ::completion::search {{text ""}} {
    ::completion::msg_debug "::completion::search($text)" "searches"
    set ::completion::erase_text $::completion::current_text
    if {[string range $text 0 0] eq "."} {
        ::completion::skipping_search $text
        return
    }
    if {[winfo exists .pop.f.lb]} {
        .pop.f.lb configure -selectbackground $::completion::config(bg)
    }
    set ::completion::current_search_mode 0
    if {$text ne ""} {
        set ::completion::current_text $text
        set ::completion::erase_text $text
        set ::should_restore False
    } elseif { !$::completion::completion_text_updated } {
        set ::previous_current_text $::completion::current_text
        set ::completion::current_text ""
        set ::should_restore True
    }
    ::completion::trimspaces

    set pattern "$::completion::current_text"
    set pattern [::completion::fix_pattern $pattern]

    set ::completion::completions [lsearch -all -inline -regexp -nocase $::completion::all_externals $pattern]
    if {$::should_restore} {
        set ::completion::current_text $::previous_current_text
    }
    ::completion::update_completions_gui
}

proc ::completion::fix_pattern {pattern} {
    set pattern [string map {"+" "\\+"} $pattern]
    set pattern [string map {"*" "\\*"} $pattern]
    set skippingPrefix [string range $pattern 0 0]
    set skippingString [string range $pattern 1 end]
    set skippingString [string map {"." "\\."} $skippingString]
    set pattern "$skippingPrefix$skippingString"
    return $pattern
}

proc ::completion::update_completions_gui {} {
    if {[winfo exists .pop.f.lb]} {
        ::completion::scrollbar_check
        if {$::completion::completions == {}} { ::completion::set_empty_listbox }
        if {[llength $::completion::completions] > 1} {
            .pop.f.lb configure -state normal
            .pop.f.lb select clear 0 end
            .pop.f.lb select set 0 0
            .pop.f.lb yview scroll -100 page
        }
    }
}

proc ::completion::unique {} {
    return 0
}

proc ::completion::valid {} {
    return [expr {[lindex $::completion::completions 0] ne "(empty)"}]
}

proc ::completion::set_empty_listbox {} {
    if {[winfo exists .pop.f.lb]} {
        ::completion::scrollbar_check
        .pop.f.lb configure -state disabled
    }
    set ::completion::completions {"(empty)"}
}

proc ::completion::increment {{amount 1}} {
    if {$::completion::focus != "pop"} {
        focus .pop.f.lb
        set ::completion::focus "pop"
    }
    set selected [.pop.f.lb curselection]
    if { ![ string is integer -strict $selected] } {
        return
    }
    set updated [expr {($selected + $amount) % [llength $::completion::completions]}]
    .pop.f.lb selection clear 0 end
    .pop.f.lb selection set $updated
    .pop.f.lb see $updated
}

proc ::completion::choose_selected {} {
    if {[::completion::valid]} {
        set selected_index [.pop.f.lb curselection]
        ::completion::popup_destroy
        set choosen_item [lindex $::completion::completions $selected_index]
        ::completion::replace_text $choosen_item
        set ::completion::current_text ""
        ::completion::set_empty_listbox
    }
}

proc ::completion::update_modifiers {key pressed_or_released} {
    switch -- $key {
        "Shift_L"   { set ::completion::is_shift_down $pressed_or_released }
        "Shift_R"   { set ::completion::is_shift_down $pressed_or_released }
        "Control_L" { set ::completion::is_ctrl_down $pressed_or_released }
        "Control_R" { set ::completion::is_ctrl_down $pressed_or_released }
        "Alt_L"     { set ::completion::is_alt_down $pressed_or_released }
        "Alt_R"     { set ::completion::is_alt_down $pressed_or_released }
    }
}

proc ::completion::keypress {key unicode} {
    ::completion::update_modifiers $key 1
    switch -- $unicode {
        "~~" { ::completion::insert_key "~" }
    }
}

proc ::completion::lb_keyrelease {key unicode} {
    if {$::completion::waiting_trigger_keyrelease eq 1} {
        return
    }
    ::completion::update_modifiers $key 0
    set ::completion::completion_text_updated 0
    if {[regexp {^[a-zA-Z0-9~/\._\+\-]{1}$} $key]} {
        ::completion::insert_key $key; return
    }
    switch -- $key {
        "space"     { ::completion::insert_key " " }
        "Return"    { ::completion::choose_selected }
        "BackSpace" { ::completion::chop }
        "comma" { ::completion::insert_key "," }
        "semicolon" { ::completion::insert_key ";" }
        "period" { ::completion::insert_key "." }
        "underscore" { ::completion::insert_key "_" }
        "equal" { ::completion::insert_key "+" }
        "minus" { ::completion::insert_key "-" }
        "slash" { ::completion::insert_key "/" }
        "exclam" { ::completion::insert_key "!" }
        "at" { ::completion::insert_key "@" }
        "numbersign" { ::completion::insert_key "#" }
        "dollar" { ::completion::insert_key "$" }
        "percent" { ::completion::insert_key "%" }
        "ampersand" { ::completion::insert_key "&" }
        "plus" { ::completion::insert_key "+" }
    }
}

proc ::completion::text_keys {key} {
    ::completion::msg_debug "~text_keys~ key pressed was $key\n" "key_event"
    set ::completion::completion_text_updated 0
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
        after 10; ::completion::search
    } elseif {$key eq "Return"} {
        ::completion::choose_or_unedit
    }
}

proc ::completion::insert_key {key} {
    scan $key %c keynum
    ::completion::sendKeyDown $keynum
    append ::completion::current_text $key
    ::completion::search $::completion::current_text
    set ::completion::focus "canvas"
    pdtk_text_editing $::completion::toplevel $::completion::current_tag 1
    set ::completion::completion_text_updated 0
}

proc ::completion::erase_text {} {
    set i [expr {[string length $::completion::erase_text] + 2}]
    while {--$i > 0} {
        ::completion::sendKeyDownAndUp 8
        incr i -1
    }
}

proc ::completion::replace_text {args} {
    ::completion::erase_text
    set text ""
    if { ( !$::completion::config(auto_complete_libs) && !$::completion::is_shift_down) ||
         (  $::completion::config(auto_complete_libs) &&  $::completion::is_shift_down)
         } {
        set args [split $args /]
        set args [lindex $args end]
    }
    foreach arg $args { set text [concat $text $arg] }
    for {set i 0} {$i < [string length $text]} {incr i 1} {
        set cha [string index $text $i]
        scan $cha %c keynum
        ::completion::sendKeyDown $keynum
    }
    set ::completion::erase_text $text
    set ::completion::completion_text_updated 1
}

proc ::completion::choose_or_unedit {} {
    if {[winfo exists .pop] && [::completion::valid]} {
        ::completion::choose_selected
    } {
        ::completion::text_unedit
    }
}

proc ::completion::text_unedit {} {
    pdsend "$::completion::focused_window reselect"
    set ::completion::new_object 0
    set ::completion::completion_text_updated 0
}

proc ::completion::chop {} {
    if {$::completion::is_shift_down} {
        ::completion::erase_text
        set ::completion::current_text ""
        ::completion::search
        return
    }
    ::completion::sendKeyDownAndUp 8
    set ::completion::current_text [string replace $::completion::current_text end end]
    ::completion::search $::completion::current_text
    if {[winfo exists .pop]} {
        .pop.f.lb selection clear 0 end
        .pop.f.lb selection set 0
    }
    set ::completion::focus "canvas"
}

proc ::completion::popup_draw {} {
    if {![winfo exists .pop]} {
        set screen_w [winfo screenwidth $::completion::current_canvas]
        set screen_h [winfo screenheight $::completion::current_canvas]
        set popup_width 40
        set menuheight 32
        if {$::windowingsystem ne "aqua"} { incr menuheight 24 }
        set geom [wm geometry $::completion::toplevel]
        set decoLeft 0
        set decoTop 0
        regexp -- {([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)} $geom -> \
            width height decoLeft decoTop
        set left [expr {$decoLeft + $::completion::editx}]
        set top [expr {$decoTop + $::completion::edity + $menuheight}]
        catch { destroy .pop }
        toplevel .pop
        wm overrideredirect .pop 1
        if {$::windowingsystem eq "aqua"} {
            raise .pop
        }
        wm geometry .pop +$left+$top
        frame .pop.f -takefocus 0

        pack configure .pop.f
        .pop.f configure -relief solid -borderwidth 1 -background white

        set currentbackground $::completion::config(bg)

        listbox .pop.f.lb \
            -selectmode browse \
            -width $popup_width \
            -height $::completion::config(n_lines) \
            -listvariable ::completion::completions -activestyle none \
            -highlightcolor white \
            -selectbackground $currentbackground \
            -selectforeground white \
            -yscrollcommand [list .pop.f.sb set] -takefocus 1 \
            -disabledforeground #333333

        pack .pop.f.lb -side left -expand 1 -fill both
        .pop.f.lb configure -relief flat \
            -font [list $::completion::config(font) $::completion::config(font_size)] \
            -state normal

        pack .pop.f.lb [scrollbar ".pop.f.sb" -command [list .pop.f.lb yview] -takefocus 0] \
            -side left -fill y -anchor w
        bind .pop.f.lb <Escape> {after idle { ::completion::popup_destroy 1 }}
        bind .pop.f.lb <KeyRelease> {::completion::lb_keyrelease %K %A}
        bind .pop.f.lb <Key> {after idle {::completion::keypress %K %A}}
        bind .pop.f.lb <ButtonRelease> {
            if { %b eq 1} {
                after idle {::completion::choose_selected}
            }
        }

        bind .pop.f.lb <Up> {::completion::increment -1 ; break}
        bind .pop.f.lb <Down> {::completion::increment 1 ; break}
        bind .pop.f.lb <Control-Up> {after idle {::completion::increment -10} ; break}
        bind .pop.f.lb <Control-Down> {after idle {::completion::increment 10} ; break}

        bind .pop.f.lb <Prior> {after idle {::completion::increment -20} ; break}
        bind .pop.f.lb <Next> {after idle {::completion::increment 20} ; break}

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
        set ::completion::focus "pop"
        .pop.f.lb selection set 0 0
        set height [winfo reqheight .pop.f.lb]
        if { [expr {$left+$popup_width*8>$screen_w}] } {
            set left [expr {$screen_w-$popup_width*8} ]
        }
        if {$::windowingsystem eq "win32"} {
            incr screen_h [ expr {-1*$screen_h/7} ]
        }
        if { [expr {$top+$height>$screen_h}] } {
            set top [expr {$screen_h-$height} ]
            wm geometry .pop +$left+$top
        }
    }
}

proc ::completion::popup_destroy {{unbind 0}} {
    catch { destroy .pop }
    if {$::completion::current_canvas ne ""} {
        focus -force $::completion::current_canvas
    }
    set ::completion::focus "canvas"
    if {$unbind} {
        bind $::completion::current_canvas <KeyRelease> {}
    }
    set ::completion::current_text ""
}

proc ::completion::scrollbar_check {} {
    if {[winfo exists .pop]} {
        if {[llength $::completion::completions] < $::completion::config(max_lines)} {
            pack forget .pop.f.sb
        } else {
            pack .pop.f.sb -side left -fill y
        }
    }
}

############################################################
# utils

proc ::completion::prefix {s1 s2} {
    regexp {^(.*).*\0\1} "$s1\0$s2" all pref
    return $pref
}

proc ::completion::trimspaces {} {
    set ::completion::current_text [string trimright $::completion::current_text " "]
}

# just in case.
bind all <$::modifier-Key-Return> {pdsend "$::completion::focused_window reselect"}

###########################################################
# main

::completion::init

