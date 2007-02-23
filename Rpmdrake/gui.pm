package Rpmdrake::gui;
#*****************************************************************************
#
#  Copyright (c) 2002 Guillaume Cottenceau
#  Copyright (c) 2002-2007 Thierry Vignaud <tvignaud@mandriva.com>
#  Copyright (c) 2003, 2004, 2005 MandrakeSoft SA
#  Copyright (c) 2005-2007 Mandriva SA
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2, as
#  published by the Free Software Foundation.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
#*****************************************************************************
#
# $Id$

use strict;
our @ISA = qw(Exporter);
use lib qw(/usr/lib/libDrakX);

use common;
use mygtk2 qw(gtknew); #- do not import gtkadd which conflicts with ugtk2 version

use ugtk2 qw(:helpers :wrappers);
use rpmdrake;
use Rpmdrake::formatting;
use Rpmdrake::init;
use Rpmdrake::icon;
use Rpmdrake::pkg;
use Rpmdrake::icon;
use Gtk2::Gdk::Keysyms;

our @EXPORT = qw(ask_browse_tree_given_widgets_for_rpmdrake build_tree callback_choices closure_removal do_action get_info is_locale_available pkgs_provider reset_search set_node_state switch_pkg_list_mode toggle_nodes
            $clear_button $dont_show_selections $find_entry $force_displaying_group $force_rebuild @initial_selection $pkgs $size_free $size_selected $urpm);

our $dont_show_selections = $> ? 1 : 0;

our ($descriptions, %filter_methods, $force_displaying_group, $force_rebuild, @initial_selection, $initial_selection_done, $pkgs, $size_free, $size_selected, $urpm);


sub format_pkg_simplifiedinfo {
    my ($pkgs, $key, $urpm, $descriptions) = @_;
    my ($name, $_version) = split_fullname($key);
    my $medium = pkg2medium($pkgs->{$key}{pkg}, $urpm)->{name};
    my $update_descr = $pkgs->{$key}{pkg}->flag_upgrade && $descriptions->{$name}{pre} && $descriptions->{$name}{medium} eq $medium;
    my $s = ugtk2::markup_to_TextView_format(join("\n", format_header($name . ' - ' . translate($pkgs->{$key}{summary})) .
      # workaround gtk+ bug where GtkTextView wronly limit embedded widget size to bigger line's width (#25533):
                                                      "\x{200b} \x{feff}" . ' ' x 120,
      if_($update_descr, # is it an update?
	  format_field(N("Importance: ")) . escape_text_for_TextView_markup_format($descriptions->{$name}{importance}),
	  format_field(N("Reason for update: ")) . escape_text_for_TextView_markup_format(rpm_description($descriptions->{$name}{pre})),
      ),
      '')); # extra empty line
    if ($update_descr) {
        push @$s, [ my $link = gtkshow(Gtk2::LinkButton->new($descriptions->{$name}{URL}, N("Security advisory"))) ];
        $link->set_uri_hook(sub {
            my (undef, $url) = @_;
            run_program::raw({ detach => 1 }, 'www-browser', $url);
        });
      }

    push @$s, @{ ugtk2::markup_to_TextView_format(join("\n",
      (escape_text_for_TextView_markup_format($pkgs->{$key}{description} || $descriptions->{$name}{description}) || '<i>' . N("No description") . '</i>')
    )) };
    push @$s, [ "\n" ];
    push @$s, [ gtkadd(gtkshow(my $exp = Gtk2::Expander->new(format_field(N("Files:")))),
                       gtknew('TextView', text => 
                                      exists $pkgs->{$key}{files} ?
                                          ugtk2::markup_to_TextView_format('<tt>' . join("\n", map { "\x{200e}$_" } @{$pkgs->{$key}{files}}) . '</tt>') #- to highlight information
                           : N("(Not available)"),
                   )) ];
    $exp->set_use_markup(1);
    push @$s, [ "\n\n" ];
    push @$s, [ gtkadd(gtkshow(my $exp2 = Gtk2::Expander->new(format_field(N("Changelog:")))),
                       gtknew('TextView', text => $pkgs->{$key}{changelog} || N("(Not available)"))
                   ) ];
    $exp2->set_use_markup(1);
    $s;

}

sub format_pkg_info {
    my ($pkgs, $key, $urpm, $descriptions) = @_;
    my ($name, $version) = split_fullname($key);
    my @files = (
	format_field(N("Files:\n")),
	exists $pkgs->{$key}{files}
	    ? '<tt>' . join("\n", map { "\x{200e}$_" } @{$pkgs->{$key}{files}}) . '</tt>' #- to highlight information
	    : N("(Not available)"),
    );
    my @chglo = (format_field(N("Changelog:\n")), ($pkgs->{$key}{changelog} ? @{$pkgs->{$key}{changelog}} : N("(Not available)")));
    my @source_info = (
	$MODE eq 'remove' || !@$max_info_in_descr
	    ? ()
	    : (
		format_field(N("Medium: ")) . pkg2medium($pkgs->{$key}{pkg}, $urpm)->{name},
		format_field(N("Currently installed version: ")) . find_installed_version($pkgs->{$key}{pkg}),
	    )
    );
    my @max_info = @$max_info_in_descr && $changelog_first ? (@chglo, @files) : (@files, '', @chglo);
    ugtk2::markup_to_TextView_format(join("\n", format_field(N("Name: ")) . $name,
      format_field(N("Version: ")) . $version,
      format_field(N("Architecture: ")) . $pkgs->{$key}{pkg}->arch,
      format_field(N("Size: ")) . N("%s KB", int($pkgs->{$key}{pkg}->size/1024)),
      if_(
	  $MODE eq 'update',
	  format_field(N("Importance: ")) . $descriptions->{$name}{importance}
      ),
      @source_info,
      '', # extra empty line
      format_field(N("Summary: ")) . $pkgs->{$key}{summary},
      '', # extra empty line
      if_(
	  $MODE eq 'update',
	  format_field(N("Reason for update: ")) . rpm_description($descriptions->{$name}{pre}),
      ),
      format_field(N("Description: ")), ($pkgs->{$key}{description} || $descriptions->{$name}{description} || N("No description")),
      @max_info,
    ));
}

sub node_state {
    my $pkg = $pkgs->{$_[0]};
    my $urpm_obj = $pkg->{pkg};
    #- checks $_[0] -> hack for partial tree displaying
    $_[0] ? $pkg->{selected} ?
      ($urpm_obj->flag_installed ? ($urpm_obj->flag_upgrade ? 'to_install' : 'to_remove') : 'to_install')
        : ($urpm_obj->flag_installed ? 
             ($urpm_obj->flag_upgrade ? 'to_update' : 'installed')
               : ($urpm_obj->flag_base ? '/usr/share/rpmdrake/icons/base.png' : 'uninstalled')) : 'XXX';
}

my ($common, $w, %wtree, %ptree, %pix, %node_state, %state_stats);

sub set_node_state_flat {
    my ($iter, $state, $model) = @_;
    print "STATE: $state\n";
    $state eq 'XXX' and return;
    $pix{$state} ||= gtkcreate_pixbuf($state);
    $model ||= $w->{tree_model};
    $model->set($iter, 1 => $pix{$state});
    $model->set($iter, 2 => $state);
}

sub set_node_state_tree {
    my ($iter, $state, $model) = @_;
    $model ||= $w->{tree_model};
    my $iter_str = $model->get_path_str($iter);
    ($state eq 'XXX' || !$state) and return;
    $pix{$state} ||= gtkcreate_pixbuf('state_' . $state);
    if ($node_state{$iter_str} ne $state) {
        my $parent;
        if (!$model->iter_has_child($iter) && ($parent = $model->iter_parent($iter))) {
            my $parent_str = $model->get_path_str($parent);
            my $stats = $state_stats{$parent_str} ||= {}; $stats->{$node_state{$iter_str}}--; $stats->{$state}++;
            my @list = grep { $stats->{$_} > 0 } keys %$stats;
            my $new_state = @list == 1 ? $list[0] : 'semiselected';
            $node_state{$parent_str} ne $new_state and
              set_node_state_tree($parent, $new_state);
        }
        $model->set($iter, 1 => $pix{$state});
        $model->set($iter, 2 => $state);
        #$node_state{$iter_str} = $state;  #- cache for efficiency
    } else  {
    }
}

sub set_node_state {
    $common->{state}{flat} ? set_node_state_flat(@_) : \&set_node_state_tree(@_);
}

sub set_leaf_state {
    my ($leaf, $state, $model) = @_;
    set_node_state($_, $state, $model) foreach @{$ptree{$leaf}};
}

sub add_parent {
    my ($root, $state) = @_;
    $root or return undef;
    if (my $w = $wtree{$root}) { return $w }
    my $s; foreach (split '\|', $root) {
        my $s2 = $s ? "$s|$_" : $_;
        $wtree{$s2} ||= do {
            my $pixbuf = get_icon($s2, $s);
            my $iter = $w->{tree_model}->append_set($s ? add_parent($s, $state, get_icon($s)) : undef, [ 0 => $_, if_($pixbuf, 2 => $pixbuf) ]);
            $iter;
        };
        $s = $s2;
    }
        set_node_state($wtree{$s}, $state); #- use this state by default as tree is building.
    $wtree{$s};
}

# ask_browse_tree_given_widgets will run gtk+ loop. its main parameter "common" is a hash containing:
# - a "widgets" subhash which holds:
#   o a "w" reference on a ugtk2 object
#   o "tree" & "info" references a TreeView
#   o "info" is a TextView
#   o "tree_model" is the associated model of "tree"
#   o "status" references a Label
# - some methods: get_info, node_state, build_tree, partialsel_unsel, grep_unselected, rebuild_tree, toggle_nodes, get_status
# - "tree_submode": the default mode (by group, mandriva choice), ...
# - "state": a hash of misc flags: => { flat => '0' },
#   o "flat": is the tree flat or not
# - "tree_mode": mode of the tree ("mandrake_choices", "by_group", ...) (mainly used by rpmdrake)
          
sub ask_browse_tree_given_widgets_for_rpmdrake {
    ($common) = @_;
    $w = $common->{widgets};

    $w->{detail_list} ||= $w->{tree};
    $w->{detail_list_model} ||= $w->{tree_model};

    my ($prev_label);
    my $update_size = sub {
	if ($w->{status}) {
	    my $new_label = $common->{get_status}();
	    $prev_label ne $new_label and $w->{status}->set($prev_label = $new_label);
	}
    };  

    $common->{add_parent} = \&add_parent;
    my $add_node = sub {
	my ($leaf, $root, $options) = @_;
	my $state = node_state($leaf) or return;
	if ($leaf) {
	    my $iter;
         if (is_a_package($leaf)) {
             $iter = $w->{detail_list_model}->append_set([ 0 => $leaf ]);
             set_node_state($iter, $state, $w->{detail_list_model});
         } else {
             $iter = $w->{tree_model}->append_set(add_parent($root, $state), [ 0 => $leaf ]);
         }
	    push @{$ptree{$leaf}}, $iter;
	} else {
	    my $parent = add_parent($root, $state);
	    #- hackery for partial displaying of trees, used in rpmdrake:
	    #- if leaf is void, we may create the parent and one child (to have the [+] in front of the parent in the ctree)
	    #- though we use '' as the label of the child; then rpmdrake will connect on tree_expand, and whenever
	    #- the first child has '' as the label, it will remove the child and add all the "right" children
	    $options->{nochild} or $w->{tree_model}->append_set($parent, [ 0 => '' ]);  # test $leaf?
	}
    };
    my $clear_all_caches = sub {
	foreach (values %ptree) {
	    foreach my $n (@$_) {
		delete $node_state{$w->{detail_list_model}->get_path_str($n)};
	    }
	}
	foreach (values %wtree) {
         foreach my $model ($w->{tree_model}) {
	    my $iter_str = $model->get_path_str($_);
	    delete $node_state{$iter_str};
	    delete $state_stats{$iter_str};
         }
	}
	%ptree = %wtree = ();
    };
    $common->{delete_all} = sub {
	$clear_all_caches->();
	$w->{detail_list_model}->clear;
	$w->{tree_model}->clear;
    };
    $common->{rebuild_tree} = sub {
	$common->{delete_all}->();
	$common->{build_tree}($add_node, $common->{state}{flat}, $common->{tree_mode});
	&$update_size;
    };
    $common->{delete_category} = sub {
	my ($cat) = @_;
	exists $wtree{$cat} or return;
	foreach (keys %ptree) {
	    my @to_remove;
	    foreach my $node (@{$ptree{$_}}) {
		my $category;
		my $parent = $node;
		my @parents;
		while ($parent = $w->{tree_model}->iter_parent($parent)) {    #- LEAKS
		    my $parent_name = $w->{tree_model}->get($parent, 0);
		    $category = $category ? "$parent_name|$category" : $parent_name;
		    $_->[1] = "$parent_name|$_->[1]" foreach @parents;
		    push @parents, [ $parent, $category ];
		}
		if ($category =~ /^\Q$cat/) {
		    push @to_remove, $node;
		    foreach (@parents) {
			next if $_->[1] eq $cat || !exists $wtree{$_->[1]};
			delete $wtree{$_->[1]};
			delete $node_state{$w->{tree_model}->get_path_str($_->[0])};
			delete $state_stats{$w->{tree_model}->get_path_str($_->[0])};
		    }
		}
	    }
	    foreach (@to_remove) {
		delete $node_state{$w->{tree_model}->get_path_str($_)};
	    }
	    @{$ptree{$_}} = difference2($ptree{$_}, \@to_remove);
	}
	if (exists $wtree{$cat}) {
	    my $iter_str = $w->{tree_model}->get_path_str($wtree{$cat});
	    delete $node_state{$iter_str};
	    delete $state_stats{$iter_str};
	    $w->{tree_model}->remove($wtree{$cat});
	    delete $wtree{$cat};
	}
	&$update_size;
    };
    $common->{add_nodes} = sub {
	my (@nodes) = @_;
	$w->{detail_list_model}->clear;
	$w->{detail_list}->scroll_to_point(0, 0);
	$add_node->($_->[0], $_->[1], $_->[2]) foreach @nodes;
	&$update_size;
    };
    
    $common->{display_info} = sub {
        gtktext_insert($w->{info}, get_info($_[0], $w->{tree}->window));
        $w->{info}->scroll_to_iter($w->{info}->get_buffer->get_start_iter, 0, 0, 0, 0);
        0;
    };
    my $children = sub { map { $w->{detail_list_model}->get($_, 0) } gtktreeview_children($w->{detail_list_model}, $_[0]) };
    $common->{toggle_all} = sub {
        my ($_val) = @_;
		my @l = $children->() or return;

		my @unsel = $common->{grep_unselected}(@l);
		my @p = @unsel ?
		  #- not all is selected, select all if no option to potentially override
		  (exists $common->{partialsel_unsel} && $common->{partialsel_unsel}->(\@unsel, \@l) ? difference2(\@l, \@unsel) : @unsel)
		  : @l;
		toggle_nodes($w->{tree}->window, $w->{detail_list_model}, \&set_leaf_state, undef, @p);
		&$update_size;
    };
    my $fast_toggle = sub {
        my ($iter) = @_;
        gtkset_mousecursor_wait($w->{w}{rwindow}->window);
        toggle_nodes($w->{tree}->window, $w->{detail_list_model}, \&set_leaf_state, $w->{detail_list_model}->get($iter, 2), $w->{detail_list_model}->get($iter, 0));
	    &$update_size;
	    gtkset_mousecursor_normal($w->{w}{rwindow}->window);
    };
    $w->{detail_list}->get_selection->signal_connect(changed => sub {
	my ($model, $iter) = $_[0]->get_selected;
	$model && $iter or return;
     $common->{display_info}($model->get($iter, 0));
 });
    $w->{detail_list}->signal_connect(button_press_event => sub {  #- not too good, but CellRendererPixbuf does not have the needed signals :(
	my ($path, $column) = $w->{detail_list}->get_path_at_pos($_[1]->x, $_[1]->y);
	if ($path && $column && $column->{is_pix}) {
	    my $iter = $w->{detail_list_model}->get_iter($path);
	    $fast_toggle->($iter) if $iter;
	}
        0;
    });
    $w->{detail_list}->signal_connect(key_press_event => sub {
	my $c = chr($_[1]->keyval & 0xff);
	if ($_[1]->keyval >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ') {
         my ($model, $iter) = $w->{detail_list}->get_selection->get_selected;
	    $fast_toggle->($iter) if $model && $iter;
	}
	0;
    });
    $common->{rebuild_tree}->();
    &$update_size;
    $common->{initial_selection} and toggle_nodes($w->{tree}->window, $w->{detail_list_model}, \&set_leaf_state, undef, @{$common->{initial_selection}});
    #my $_b = before_leaving { $clear_all_caches->() };
    $common->{init_callback}->() if $common->{init_callback};
    $w->{w}->main;
}

our ($clear_button, $find_entry);

sub reset_search() {
    $clear_button and $clear_button->set_sensitive(0);
    $find_entry and $find_entry->set_text("");
}

sub is_a_package {
    my ($pkg) = @_;
    return exists $pkgs->{$pkg};
}

sub switch_pkg_list_mode {
    my ($mode) = @_;
    return if !$mode;
    return if !$filter_methods{$mode};
    $force_displaying_group = 1;
    $filter_methods{$mode}->();
}

sub pkgs_provider {
    my ($options, $mode) = @_;
    return if !$mode;
    my $h = &get_pkgs($urpm, $options); # was given (1, @_) for updates
    ($urpm, $descriptions) = @$h{qw(urpm update_descr)};
    %filter_methods = (
        all => sub { $pkgs = { map { %{$h->{$_}} } qw(installed installable updates) } },
        installed => sub { $pkgs = $h->{installed} },
        non_installed => sub { $pkgs = $h->{installable} },
        all_updates => sub {
            my @pkgs = grep { my $p = $h->{installable}{$_}; $p->{pkg} && !$p->{selected} && $p->{pkg}->flag_installed && $p->{pkg}->flag_upgrade } keys %{$h->{installable}};
            $pkgs = {
                (map { $_ => $h->{updates}{$_} } keys %{$h->{updates}}),
                (map { $_ => $h->{installable}{$_} } @pkgs)
            };
        },
    );
    if (!$initial_selection_done) {
        $filter_methods{all}->();
        @initial_selection = grep { $pkgs->{$_}{selected} } keys %$pkgs;
        $initial_selection_done = 1;
    }
    foreach my $importance (qw(bugfix security normal)) {
        $filter_methods{$importance} = sub {
            $pkgs = $h->{updates};
            $pkgs = { map { $_ => $pkgs->{$_} } grep { 
                my ($name, $_version) = split_fullname($_);
                $descriptions->{$name}{importance} eq $importance } keys %$pkgs };
        };
    }
    $filter_methods{mandrake_choices} = $filter_methods{non_installed};
    switch_pkg_list_mode($mode);
}

sub closure_removal {
    $urpm->{state} = {};
    urpm::select::find_packages_to_remove($urpm, $urpm->{state}, \@_);
}

sub is_locale_available {
    any { $urpm->{depslist}[$_]->flag_selected } keys %{$urpm->{provides}{$_[0]} || {}} and return 1;
    my $found;
    $db->traverse_tag('name', [ $_ ], sub { $found ||= 1 });
    return $found;
}

sub callback_choices {
    my (undef, undef, undef, $choices) = @_;
    foreach my $pkg (@$choices) {
        foreach ($pkg->requires_nosense) {
            /locales-/ or next;
            is_locale_available($_) and return $pkg;
        }
    }
    my $callback = sub { interactive_msg(N("More information on package..."), get_info($_[0]), scroll => 1) };
    $choices = [ sort { $a->name cmp $b->name } @$choices ];
    my @choices = interactive_list_(N("Please choose"), scalar(@$choices) == 1 ? 
    N("The following package is needed:") : N("One of the following packages is needed:"),
                                    [ map { urpm_name($_) } @$choices ], $callback);
    $choices->[$choices[0]];
}

sub toggle_nodes {
    my ($widget, $model, $set_state, $old_state, @nodes) = @_;
    @nodes = grep { exists $pkgs->{$_} } @nodes
      or return;
    #- avoid selecting too many packages at once
    return if !$dont_show_selections && @nodes > 2000;
    my $new_state = !$pkgs->{$nodes[0]}{selected};

    my @nodes_with_deps;
    my $deps_msg = sub {
        return 1 if $dont_show_selections;
        my ($title, $msg, $nodes, $nodes_with_deps) = @_;
        my @deps = sort { $a cmp $b } difference2($nodes_with_deps, $nodes);
        @deps > 0 or return 1;
      deps_msg_again:
        my $results = interactive_msg(
            $title, $msg . urpm::select::translate_why_removed($urpm, $urpm->{state}, @deps),
            yesno => [ N("Cancel"), N("More info"), N("Ok") ],
            scroll => 1,
        );
        if ($results eq
		    #-PO: Keep it short, this is gonna be on a button
		    N("More info")) {
            interactive_packtable(
                N("Information on packages"),
                $::main_window,
                undef,
                [ map { my $pkg = $_;
                        [ gtknew('HBox', children_tight => [ gtkset_selectable(gtknew('Label', text => $pkg), 1) ]),
                          gtknew('Button', text => N("More information on package..."), 
                                 clicked => sub {
                                     interactive_msg(N("More information on package..."), get_info($pkg), scroll => 1);
                                 }) ] } @deps ],
                [ gtknew('Button', text => N("Ok"), 
                         clicked => sub { Gtk2->main_quit }) ]
            );
            goto deps_msg_again;
        } else {
            return $results eq N("Ok");
        }
    };                          # deps_msg

    if (member($old_state, qw(to_remove installed))) { # remove pacckages
        if ($new_state) {
            my @remove;
            slow_func($widget, sub { @remove = closure_removal(@nodes) });
            @nodes_with_deps = grep { !$pkgs->{$_}{selected} && !/^basesystem/ } @remove;
            $deps_msg->(N("Some additional packages need to be removed"),
                        formatAlaTeX(N("Because of their dependencies, the following package(s) also need to be\nremoved:")) . "\n\n",
                        \@nodes, \@nodes_with_deps) or @nodes_with_deps = ();
            my @impossible_to_remove;
            foreach (grep { exists $pkgs->{$_}{base} } @remove) {
                ${$pkgs->{$_}{base}} == 1 ? push @impossible_to_remove, $_ : ${$pkgs->{$_}{base}}--;
            }
            @impossible_to_remove and interactive_msg(N("Some packages can't be removed"),
                                                      N("Removing these packages would break your system, sorry:\n\n") .
                                                        formatlistpkg(@impossible_to_remove));
            @nodes_with_deps = difference2(\@nodes_with_deps, \@impossible_to_remove);
        } else {
            slow_func($widget,
                      sub { @nodes_with_deps = grep { intersection(\@nodes, [ closure_removal($_) ]) }
                              grep { $pkgs->{$_}{selected} && !member($_, @nodes) } keys %$pkgs });
            push @nodes_with_deps, @nodes;
            $deps_msg->(N("Some packages can't be removed"),
                        N("Because of their dependencies, the following package(s) must be\nunselected now:\n\n"),
                        \@nodes, \@nodes_with_deps) or @nodes_with_deps = ();
            $pkgs->{$_}{base} && ${$pkgs->{$_}{base}}++ foreach @nodes_with_deps;
        }
    } else {
        if ($new_state) {
            if (@nodes > 1) {
                #- unselect i18n packages of which locales is not already present (happens when user clicks on KDE group)
                my @bad_i18n_pkgs;
                foreach my $sel (@nodes) {
                    foreach ($pkgs->{$sel}{pkg}->requires_nosense) {
                        /locales-([^-]+)/ or next;
                        $sel =~ /-$1[-_]/ && !is_locale_available($_) and push @bad_i18n_pkgs, $sel;
                    }
                }
                @nodes = difference2(\@nodes, \@bad_i18n_pkgs);
            }
            my @requested;
            slow_func(
                $widget,
                sub {
                    @requested = $urpm->resolve_requested(
                        $db, $urpm->{state},
                        { map { $pkgs->{$_}{pkg}->id => 1 } @nodes },
                        callback_choices => \&callback_choices,
                    );
                },
            );
            @nodes_with_deps = map { urpm_name($_) } @requested;
            if (!$deps_msg->(N("Additional packages needed"),
                             N("To satisfy dependencies, the following package(s) also need\nto be installed:\n\n"),
                             \@nodes, \@nodes_with_deps)) {
                @nodes_with_deps = ();
                $urpm->disable_selected($db, $urpm->{state}, @requested);
                goto packages_selection_ok;
            }

            if (my @cant = sort(difference2(\@nodes, \@nodes_with_deps))) {
                my @ask_unselect = urpm::select::unselected_packages($urpm, $urpm->{state});
                my @reasons = map {
                    my $cant = $_;
                    my $unsel = find { $_ eq $cant } @ask_unselect;
                    $unsel
                      ? join("\n", urpm::select::translate_why_unselected($urpm, $urpm->{state}, $unsel))
                        : ($pkgs->{$_}{pkg}->flag_skip ? N("%s (belongs to the skip list)", $cant) : $cant);
                } @cant;
                my $count = @reasons;
                interactive_msg(
                    $count == 1 ? 
                    N("One package cannot be installed")
		    : N("Some packages can't be installed"),
		    $count == 1 ? 
                    N("Sorry, the following package cannot be selected:\n\n%s", join("\n", @reasons))
		    : N("Sorry, the following packages can't be selected:\n\n%s", join("\n", @reasons)),
                    scroll => 1,
                );
                foreach (@cant) {
                    $pkgs->{$_}{pkg}->set_flag_requested(0);
                    $pkgs->{$_}{pkg}->set_flag_required(0);
                }
            }
          packages_selection_ok:
        } else {
            my @unrequested;
            slow_func($widget,
                      sub { @unrequested = $urpm->disable_selected($db, $urpm->{state},
                                                                   map { $pkgs->{$_}{pkg} } @nodes) });
            @nodes_with_deps = map { urpm_name($_) } @unrequested;
            if (!$deps_msg->(N("Some packages need to be removed"),
                             N("Because of their dependencies, the following package(s) must be\nunselected now:\n\n"),
                             \@nodes, \@nodes_with_deps)) {
                @nodes_with_deps = ();
                $urpm->resolve_requested($db, $urpm->{state}, { map { $_->id => 1 } @unrequested });
                goto packages_unselection_ok;
            }
          packages_unselection_ok:
        }
    }

    foreach (@nodes_with_deps) {
        #- some deps may exist on some packages which aren't listed because
        #- not upgradable (older than what currently installed)
        exists $pkgs->{$_} or next;
        if (!$pkgs->{$_}{pkg}) { #- can't be removed  # FIXME; what about next packages in the loop?
            $pkgs->{$_}{selected} = 0;
            log::explanations("can't be removed: $_");
        } else {
            $pkgs->{$_}{selected} = $new_state;
        }
        $set_state->($_, node_state($_), $model);
        $pkgs->{$_}{pkg}
          and $size_selected += $pkgs->{$_}{pkg}->size * ($new_state ? 1 : -1);
    }
}

sub do_action {
    my ($options, $callback_action, $o_info) = @_;
    require urpm::sys;
    if (!urpm::sys::check_fs_writable()) {
        $urpm->{fatal}(1, N("Error: %s appears to be mounted read-only.", $urpm::sys::mountpoint));
        return;
    }
    if (!int(grep { $pkgs->{$_}{selected} } keys %$pkgs)) {
        interactive_msg(N("You need to select some packages first."), N("You need to select some packages first."));
        return;
    }
    my $size_added = sum(map { if_($_->flag_selected && !$_->flag_installed, $_->size) } @{$urpm->{depslist}});
    if ($MODE eq 'install' && $size_free - $size_added/1024 < 50*1024) {
        interactive_msg(N("Too many packages are selected"),
                        N("Warning: it seems that you are attempting to add so much
packages that your filesystem may run out of free diskspace,
during or after package installation ; this is particularly
dangerous and should be considered with care.

Do you really want to install all the selected packages?"), yesno => 1)
          or return;
    }
    if (!$callback_action->($urpm, $pkgs)) {
        $force_rebuild = 1;
        pkgs_provider({ skip_updating_mu => 1 }, $options->{tree_mode});
        reset_search();
        $size_selected = 0;
        (undef, $size_free) = MDK::Common::System::df('/usr');
        $options->{rebuild_tree}->();
        gtktext_insert($o_info, '') if $o_info;
    }
}


sub ctreefy {
    join('|', map { translate($_) } split m|/|, $_[0]);
}

sub build_tree {
    my ($tree, $tree_model, $elems, $options, $force_rebuild, $compssUsers, $add_node, $flat, $mode) = @_;
    my $old_mode if 0;
    $mode = $options->{rmodes}{$mode} || $mode;
    return if $old_mode eq $mode && !$force_rebuild;
    $old_mode = $mode;
    undef $force_rebuild;
    my @elems;
    my $wait; $wait = statusbar_msg(N("Please wait, listing packages...")) if $MODE ne 'update';
    gtkflush();
    if ($mode eq 'mandrake_choices') {
        foreach my $pkg (keys %$pkgs) {
            my ($name) = split_fullname($pkg);
            push @elems, [ $pkg, $_ ] foreach @{$compssUsers->{$name}};
        }
    } else {
        my @keys = keys %$pkgs;
        if (member($mode, qw(all_updates security bugfix normal))) {
            @keys = grep {
                my ($name) = split_fullname($_);
                member($descriptions->{$name}{importance}, @$mandrakeupdate_wanted_categories)
                  || ! $descriptions->{$name}{importance};
            } @keys;
            if (@keys == 0) {
                $add_node->('', N("(none)"), { nochild => 1 });
                my $explanation_only_once if 0;
                $explanation_only_once or interactive_msg(N("No update"),
                                                          N("The list of updates is empty. This means that either there is
no available update for the packages installed on your computer,
or you already installed all of them."));
                $explanation_only_once = 1;
            }
        }
        @elems = map { [ $_, !$flat && ctreefy($pkgs->{$_}{pkg}->group) ] } @keys;
    }
    my %sortmethods = (
        by_size => sub { sort { $pkgs->{$b->[0]}{pkg}->size <=> $pkgs->{$a->[0]}{pkg}->size } @_ },
        by_selection => sub { sort { $pkgs->{$b->[0]}{selected} <=> $pkgs->{$a->[0]}{selected}
                                       || uc($a->[0]) cmp uc($b->[0]) } @_ },
        by_leaves => sub {
            my $pkgs_times = 'rpm -q --qf "%{name}-%{version}-%{release} %{installtime}\n" `urpmi_rpm-find-leaves`';
            sort { $b->[1] <=> $a->[1] } grep { exists $pkgs->{$_->[0]} } map { [ split ] } run_rpm($pkgs_times);
        },
        flat => sub { no locale; sort { uc($a->[0]) cmp uc($b->[0]) } @_ },
        by_medium => sub { sort { $a->[2] <=> $b->[2] || uc($a->[0]) cmp uc($b->[0]) } @_ },
    );
    if ($flat) {
        $add_node->($_->[0], '') foreach $sortmethods{$mode || 'flat'}->(@elems);
    } else {
        if (0 && $MODE eq 'update') {
            $add_node->($_->[0], N("All")) foreach $sortmethods{flat}->(@elems);
            $tree->expand_row($tree_model->get_path($tree_model->get_iter_first), 0);
        } elsif ($mode eq 'by_source') {
            $add_node->($_->[0], $_->[1]) foreach $sortmethods{by_medium}->(map {
                my $m = pkg2medium($pkgs->{$_->[0]}{pkg}, $urpm); [ $_->[0], $m->{name}, $m->{priority} ];
            } @elems);
        } elsif ($mode eq 'by_presence') {
            $add_node->(
                $_->[0], $pkgs->{$_->[0]}{pkg}->flag_installed && !$pkgs->{$_->[0]}{pkg}->flag_skip
                  ? N("Upgradable") : N("Addable")
		    ) foreach $sortmethods{flat}->(@elems);
        } else {
            #- we populate all the groups tree at first
            %$elems = ();
            # better loop on packages, create groups tree and push packages in the proper place:
            foreach my $pkg (@elems) {
                my $grp = $pkg->[1];
                add_parent($grp);
                $elems->{$grp} ||= [];
                push @{$elems->{$grp}}, $pkg;
            }
        }
    }
    statusbar_msg_remove($wait) if defined $wait;
}

sub get_info {
    my ($key, $widget) = @_;
    #- the package information hasn't been loaded. Instead of rescanning the media, just give up.
    exists $pkgs->{$key} or return [ [ N("Description not available for this package\n") ] ];
    exists $pkgs->{$key}{description} && exists $pkgs->{$key}{files}
      or slow_func($widget, sub { extract_header($pkgs->{$key}, $urpm) });
    my $s;
    eval { $s = format_pkg_simplifiedinfo($pkgs, $key, $urpm, $descriptions) };
    if (my $err = $@) {
        $s = N("A fatal error occurred: %s.", $err);
    }
    $s;
}

1;
