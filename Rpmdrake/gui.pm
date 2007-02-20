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
use Gtk2::Gdk::Keysyms;

our @EXPORT = qw(ask_browse_tree_info_given_widgets_for_rpmdrake);


# ask_browse_tree_info_given_widgets will run gtk+ loop. its main parameter "common" is a hash containing:
# - a "widgets" subhash which holds:
#   o a "w" reference on a ugtk2 object
#   o "tree" & "info" references a TreeView
#   o "info" is a TextView
#   o "tree_model" is the associated model of "tree"
#   o "status" references a Label
# - some methods: get_info, node_state, build_tree, grep_allowed_to_toggle, partialsel_unsel, grep_unselected, rebuild_tree, toggle_nodes, check_interactive_to_toggle, get_status
# - "tree_submode": the default mode (by group, mandriva choice), ...
# - "state": a hash of misc flags: => { flat => '0' },
#   o "flat": is the tree flat or not
# - "tree_mode": mode of the tree ("mandrake_choices", "by_group", ...) (mainly used by rpmdrake)
          
sub ask_browse_tree_info_given_widgets_for_rpmdrake {
    my ($common) = @_;
    my $w = $common->{widgets};

    $w->{detail_list} ||= $w->{tree};
    $w->{detail_list_model} ||= $w->{tree_model};

    my ($prev_label);
    my (%wtree, %ptree, %pix, %node_state, %state_stats);
    my $update_size = sub {
	if ($w->{status}) {
	    my $new_label = $common->{get_status}();
	    $prev_label ne $new_label and $w->{status}->set($prev_label = $new_label);
	}
    };
    
    my $set_node_state_flat = sub {
	my ($iter, $state, $model) = @_;
	$state eq 'XXX' and return;
        $pix{$state} ||= gtkcreate_pixbuf($state);
        $model ||= $w->{tree_model};
        $model->set($iter, 1 => $pix{$state});
        $model->set($iter, 2 => $state);
    };
    my $set_node_state_tree; $set_node_state_tree = sub {
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
          $set_node_state_tree->($parent, $new_state);
	    }
            $model->set($iter, 1 => $pix{$state});
            $model->set($iter, 2 => $state);
	    #$node_state{$iter_str} = $state;  #- cache for efficiency
	} else  {
     }
    };
    my $set_node_state =
      $common->{state}{splited} || $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;

    my $set_leaf_state = sub {
	my ($leaf, $state, $model) = @_;
	$set_node_state->($_, $state, $model) foreach @{$ptree{$leaf}};
    };
    my $add_parent; $add_parent = sub {
	my ($root, $state) = @_;
	$root or return undef;
	if (my $w = $wtree{$root}) { return $w }
	my $s; foreach (split '\|', $root) {
	    my $s2 = $s ? "$s|$_" : $_;
	    $wtree{$s2} ||= do {
	    my $pixbuf = $common->{get_icon}->($s2, $s);
		my $iter = $w->{tree_model}->append_set($s ? $add_parent->($s, $state, $common->{get_icon}->($s)) : undef, [ 0 => $_, if_($pixbuf, 2 => $pixbuf) ]);
		$iter;
	    };
	    $s = $s2;
	}
	$set_node_state->($wtree{$s}, $state); #- use this state by default as tree is building.
	$wtree{$s};
    };
    $common->{add_parent} = $add_parent;
    my $add_node = sub {
	my ($leaf, $root, $options) = @_;
	my $state = $common->{node_state}($leaf) or return;
	if ($leaf) {
	    my $iter;
         if ($common->{is_a_package}->($leaf)) {
             $iter = $w->{detail_list_model}->append_set([ 0 => $leaf ]);
             $set_node_state->($iter, $state, $w->{detail_list_model});
         } else {
             $iter = $w->{tree_model}->append_set($add_parent->($root, $state), [ 0 => $leaf ]);
         }
	    push @{$ptree{$leaf}}, $iter;
	} else {
	    my $parent = $add_parent->($root, $state);
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
	$set_node_state = $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;
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
        gtktext_insert($w->{info}, $common->{get_info}($_[0]));
        $w->{info}->scroll_to_iter($w->{info}->get_buffer->get_start_iter, 0, 0, 0, 0);
        0;
    };
    my $children = sub { map { $w->{detail_list_model}->get($_, 0) } gtktreeview_children($w->{detail_list_model}, $_[0]) };
    $common->{toggle_all} = sub {
        my ($_val) = @_;
		my @l = $common->{grep_allowed_to_toggle}($children->()) or return;

		my @unsel = $common->{grep_unselected}(@l);
		my @p = @unsel ?
		  #- not all is selected, select all if no option to potentially override
		  (exists $common->{partialsel_unsel} && $common->{partialsel_unsel}->(\@unsel, \@l) ? difference2(\@l, \@unsel) : @unsel)
		  : @l;
		$common->{toggle_nodes}($set_leaf_state, undef, @p);
		&$update_size;
    };
    my $fast_toggle = sub {
        my ($iter) = @_;
        gtkset_mousecursor_wait($w->{w}{rwindow}->window);
        $common->{check_interactive_to_toggle}($iter) and $common->{toggle_nodes}($set_leaf_state, $w->{detail_list_model}->get($iter, 2), $w->{detail_list_model}->get($iter, 0));
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
    $common->{initial_selection} and $common->{toggle_nodes}($set_leaf_state, undef, @{$common->{initial_selection}});
    #my $_b = before_leaving { $clear_all_caches->() };
    $common->{init_callback}->() if $common->{init_callback};
    $w->{w}->main;
}

1;
