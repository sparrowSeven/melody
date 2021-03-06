package MT::CMS::Tag;

use strict;

sub rename_tag {
    my $app = shift;
    $app->validate_magic or return;

    my $q       = $app->query;
    my $perms   = $app->permissions;
    my $blog_id = $app->blog->id if $app->blog;
    ( $blog_id && $perms && $perms->can_edit_tags )
      || ( $app->user->is_superuser() )
      or return $app->errtrans("Permission denied.");
    my $id   = $q->param('__id');
    my $name = $q->param('tag_name')
      or return $app->error(
                  $app->translate("New name of the tag must be specified.") );
    my $obj_type  = $q->param('__type') || 'entry';
    my $obj_class = $app->model($obj_type);
    my $tag_class = $app->model('tag');
    my $ot_class  = $app->model('objecttag');
    my $tag       = $tag_class->load($id)
      or return $app->error( $app->translate("No such tag") );
    my $tag2
      = $tag_class->load( { name => $name }, { binary => { name => 1 } } );

    if ($tag2) {
        return $app->call_return if $tag->id == $tag2->id;
    }

    my $terms = { tag_id => $tag->id };
    $terms->{blog_id} = $blog_id if $blog_id;

    my $iter = $obj_class->load_iter( { (
                                            $obj_type =~ m/asset/i
                                            ? ( class => '*' )
                                            : ( class => $obj_type )
                                         )
                                      },
                                      {
                                         join =>
                                           MT::ObjectTag->join_on(
                                                           'object_id', $terms
                                           )
                                      }
    );
    my @tagged_objects;
    while ( my $o = $iter->() ) {
        $o->remove_tags( $tag->name );
        $o->add_tags($name);
        push @tagged_objects, $o;
    }
    $_->save foreach @tagged_objects;

    if ($tag2) {
        $app->add_return_arg( merged => 1 );
    }
    else {
        $app->add_return_arg( renamed => 1 );
    }
    $app->call_return;
} ## end sub rename_tag

sub js_tag_check {
    my $app       = shift;
    my $q         = $app->query;
    my $name      = $q->param('tag_name');
    my $blog_id   = $q->param('blog_id');
    my $type      = $q->param('_type') || 'entry';
    my $tag_class = $app->model('tag')
      or return $app->json_error( $app->translate("Invalid request.") );
    my $tag
      = $tag_class->load( { name => $name }, { binary => { name => 1 } } );
    my $class = $app->model($type)
      or $app->json_error( $app->translate("Invalid request.") );

    if ( $tag && $blog_id ) {
        my $ot_class = $app->model('objecttag');
        my $exist = $ot_class->exist( {
                                     object_datasource => $class->datasource,
                                     blog_id           => $blog_id,
                                     tag_id            => $tag->id
                                   }
        );
        undef $tag unless $exist;
    }
    return $app->json_result( { exists => $tag ? 'true' : 'false' } );
} ## end sub js_tag_check

sub js_tag_list {
    my $app     = shift;
    my $q       = $app->query;
    my $blog_id = $q->param('blog_id');
    my $type    = $q->param('_type') || 'entry';

    my $class = $app->model($type)
      or return $app->json_error( $app->translate("Invalid request.") );
    my $result;
    if ( my $tag_list
         = MT::Tag->cache( blog_id => $blog_id, class => $class, private => 1,
         ) )
    {
        $result = { tags => $tag_list };
    }
    else {
        $result = { tags => [] };
    }
    $app->json_result($result);
} ## end sub js_tag_list

sub js_recent_entries_for_tag {
    my $app          = shift;
    my $q            = $app->query;
    my $user         = $app->user or return;
    my $tag_class    = $app->model('tag') or return;
    my $objtag_class = $app->model('objecttag') or return;
    my $limit        = $q->param('limit') || 10;
    my $obj_ds       = $q->param('_type') || 'entry';
    my $blog_id      = $q->param('blog_id');
    my $obj_class    = $app->model($obj_ds) or return;
    my $tag_name     = $q->param('tag') or return;

    my $tag_obj = $tag_class->load( { name => $tag_name },
                                    { binary => { name => 1 } } );

    if ( !$tag_obj ) {
        return $app->json_error( $app->translate("Invalid request.") );
    }
    my $tag_id = $tag_obj->id;

    my @entries = $obj_class->load( { (
                                         $blog_id ? ( blog_id => $blog_id )
                                         : ()
                                      ),
                                      status => MT::Entry::RELEASE(),
                                    },
                                    {
                                      sort      => 'authored_on',
                                      direction => 'descend',
                                      limit     => $limit,
                                      join =>
                                        $objtag_class->join_on(
                                              'object_id',
                                              { (
                                                  $blog_id
                                                  ? ( blog_id => $blog_id )
                                                  : ()
                                                ),
                                                tag_id            => $tag_id,
                                                object_datasource => $obj_ds,
                                              }
                                        ),
                                    }
    );
    my $count =
      $obj_class->tagged_count(
                                $tag_id,
                                { (
                                      $blog_id ? ( blog_id => $blog_id ) : ()
                                   )
                                }
      );
    require MT::Template;
    require MT::Blog;
    my $tmpl = $app->load_tmpl('widget/blog_stats_recent_entries.tmpl');
    my $ctx  = $tmpl->context;
    $ctx->stash( 'blog', MT::Blog->load($blog_id) ) if $blog_id;
    $ctx->stash( 'entries', \@entries );
    $tmpl->param( 'entry_count', scalar @entries );
    $tmpl->param( 'script_url',  $app->uri );
    $tmpl->param( 'tag',         $tag_name );
    $tmpl->param( 'blog_id',     $blog_id ) if $blog_id;
    my $editable = $app->user->is_superuser;

    if ( $blog_id && !$editable ) {
        $editable = $user->permissions($blog_id)->can_edit_all_posts;
    }
    $tmpl->param( 'editable', $editable );
    my $html = $app->build_page($tmpl);
    return $app->json_result( { html => $html } );
} ## end sub js_recent_entries_for_tag

sub add_tags_to_entries {
    my $app = shift;
    my $q   = $app->query;
    my @id  = $q->param('id');

    $app->validate_magic or return;

    require MT::Tag;
    my $tags      = $q->param('itemset_action_input');
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    my @tags      = MT::Tag->split( $tag_delim, $tags );
    return $app->call_return unless @tags;

    require MT::Entry;

    my $user  = $app->user;
    my $perms = $app->permissions;
    foreach my $id (@id) {
        next unless $id;
        my $entry = MT::Entry->load($id) or next;
        next
          unless $entry
              || $user->is_superuser
              || $perms->can_edit_entry( $entry, $user );

        $entry->add_tags(@tags);
        $entry->save
          or return $app->trans_error( "Error saving entry: [_1]",
                                       $entry->errstr );
    }

    $app->add_return_arg( 'saved' => 1 );
    $app->call_return;
} ## end sub add_tags_to_entries

sub remove_tags_from_entries {
    my $app = shift;
    my $q   = $app->query;
    my @id  = $q->param('id');

    $app->validate_magic or return;

    require MT::Tag;
    my $tags      = $q->param('itemset_action_input');
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    my @tags      = MT::Tag->split( $tag_delim, $tags );
    return $app->call_return unless @tags;

    require MT::Entry;

    my $user  = $app->user;
    my $perms = $app->permissions;
    foreach my $id (@id) {
        next unless $id;
        my $entry = MT::Entry->load($id) or next;
        next
          unless $entry
              || $user->is_superuser
              || $perms->can_edit_entry( $entry, $user );
        $entry->remove_tags(@tags);
        $entry->save
          or return $app->trans_error( "Error saving entry: [_1]",
                                       $entry->errstr );
    }

    $app->add_return_arg( 'saved' => 1 );
    $app->call_return;
} ## end sub remove_tags_from_entries

sub add_tags_to_assets {
    my $app = shift;
    my $q   = $app->query;
    my @id  = $q->param('id');

    $app->validate_magic or return;

    require MT::Tag;
    my $tags      = $q->param('itemset_action_input');
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    my @tags      = MT::Tag->split( $tag_delim, $tags );
    return $app->call_return unless @tags;

    require MT::Asset;

    my $user  = $app->user;
    my $perms = $app->permissions;
    foreach my $id (@id) {
        next unless $id;
        my $asset = MT::Asset->load($id) or next;
        next unless $asset || $user->is_superuser || $perms->can_edit_assets;

        $asset->add_tags(@tags);
        $asset->save
          or return $app->trans_error( "Error saving file: [_1]",
                                       $asset->errstr );
    }

    $app->add_return_arg( 'saved' => 1 );
    $app->call_return;
} ## end sub add_tags_to_assets

sub remove_tags_from_assets {
    my $app = shift;
    my $q   = $app->query;
    my @id  = $q->param('id');

    $app->validate_magic or return;

    require MT::Tag;
    my $tags      = $q->param('itemset_action_input');
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    my @tags      = MT::Tag->split( $tag_delim, $tags );
    return $app->call_return unless @tags;

    require MT::Asset;

    my $user  = $app->user;
    my $perms = $app->permissions;
    foreach my $id (@id) {
        next unless $id;
        my $asset = MT::Asset->load($id) or next;
        next unless $asset || $user->is_superuser || $perms->can_edit_assets;
        $asset->remove_tags(@tags);
        $asset->save
          or return $app->trans_error( "Error saving file: [_1]",
                                       $asset->errstr );
    }

    $app->add_return_arg( 'saved' => 1 );
    $app->call_return;
} ## end sub remove_tags_from_assets

sub can_delete {
    my ( $eh, $app, $obj ) = @_;
    return 1 if $app->user->is_superuser();
    my $perms = $app->permissions;
    return 1
      if $app->blog
          && ( $perms->can_administer_blog() || $perms->can_edit_tags );
    return 0;
}

sub post_delete {
    my ( $eh, $app, $obj ) = @_;

    $app->log( {
                 message =>
                   $app->translate(
                                    "Tag '[_1]' (ID:[_2]) deleted by '[_3]'",
                                    $obj->name, $obj->id, $app->user->name
                   ),
                 level    => MT::Log::INFO(),
                 class    => 'system',
                 category => 'delete'
               }
    );
}

sub list_tag_for {
    my $app = shift;
    my (%params) = @_;

    my $pkg = $params{Package};

    my $q         = $app->query;
    my $blog_id   = $q->param('blog_id');
    my $list_pref = $app->list_pref('tag');
    my %param     = %$list_pref;

    my $limit = $list_pref->{rows};
    my $offset = $q->param('offset') || 0;

    my ( %terms, %arg );

    my $tag_class = $app->model('tag');
    my $ot_class  = $app->model('objecttag');
    my $total = $pkg->tag_count( $blog_id ? { blog_id => $blog_id } : undef )
      || 0;

    $arg{'sort'} = 'name';
    $arg{limit} = $limit + 1;
    if ( $total <= $limit ) {
        delete $arg{limit};
        $offset = 0;
    }
    elsif ( $total && $offset > $total - 1 ) {
        $arg{offset} = $offset = $total - $limit;
    }
    elsif ( $offset && ( ( $offset < 0 ) || ( $total - $offset < $limit ) ) )
    {
        $arg{offset} = $offset = $total - $limit;
    }
    else {
        $arg{offset} = $offset if $offset;
    }
    $arg{join} = $ot_class->join_on(
                                'tag_id',
                                {
                                  object_datasource => $pkg->datasource,
                                  ( $blog_id ? ( blog_id => $blog_id ) : () )
                                },
                                {
                                  unique => 1,
                                  'join' =>
                                    $pkg->join_on(
                                         undef,
                                         {
                                           id => \'= objecttag_object_id',
                                           (
                                             $pkg =~ m/asset/i
                                             ? ()
                                             : ( class => $pkg->class_type )
                                           )
                                         }
                                    )
                                }
    );

    my $data = build_tag_table(
                                $app,
                                load_args => [ \%terms, \%arg ],
                                'package' => $pkg,
                                param     => \%param
    );
    delete $param{tag_table} unless @$data;

    ## We tried to load $limit + 1 entries above; if we actually got
    ## $limit + 1 back, we know we have another page of entries.
    my $have_next_entry = @$data > $limit;
    pop @$data while @$data > $limit;
    if ($offset) {
        $param{prev_offset}     = 1;
        $param{prev_offset_val} = $offset - $limit;
        $param{prev_offset_val} = 0 if $param{prev_offset_val} < 0;
    }
    if ($have_next_entry) {
        $param{next_offset}     = 1;
        $param{next_offset_val} = $offset + $limit;
    }

    # load tag filters
    my $filters = $app->registry( "list_filters", "tag" ) || {};
    my $filter_key = $app->query->param('filter_key') || 'entry';
    my $filter_label = '';
    if ( my $filter = $filters->{$filter_key} ) {
        $filter_label = $filter->{label};
    }

    $param{limit}            = $limit;
    $param{offset}           = $offset;
    $param{tag_object_type}  = $params{TagObjectType};
    $param{tag_object_label} = $params{TagObjectLabel} || $pkg->class_label;
    $param{tag_object_label_plural} = $params{TagObjectLabelPlural}
      || $pkg->class_label_plural;
    $param{object_label}        = $tag_class->class_label;
    $param{object_label_plural} = $tag_class->class_label_plural;
    $param{object_type}         = 'tag';

    my $search_types = $app->search_apis( $app->blog ? 'blog' : 'system' );
    if ( grep { $_->{key} eq $param{tag_object_type} } @$search_types ) {
        $param{search_type}  = $param{tag_object_type};
        $param{search_label} = $param{tag_object_label_plural};
    }
    else {
        $param{search_type}  = 'entry';
        $param{search_label} = $app->translate("Entries");
    }

    $param{list_start}   = $offset + 1;
    $param{list_end}     = $offset + scalar @$data;
    $param{list_total}   = $total;
    $param{next_max}     = $param{list_total} - $limit;
    $param{next_max}     = 0 if ( $param{next_max} || 0 ) < $offset + 1;
    $param{list_noncron} = 1;
    $param{list_filters} = $app->list_filters('tag');
    $param{filter_key}   = $filter_key;
    $param{filter_label} = $filter_label;
    $param{link_to}      = 'list_' . lc $params{TagObjectType};

    $param{saved}         = $q->param('saved');
    $param{saved_deleted} = $q->param('saved_deleted');
    $param{nav_tags}      = 1;
    $app->add_breadcrumb( $app->translate('Tags') );
    $param{screen_class}   = "list-tag";
    $param{screen_id}      = "list-tag";
    $param{listing_screen} = 1;

    $app->load_tmpl( 'list_tag.tmpl', \%param );
} ## end sub list_tag_for

sub build_tag_table {
    my $app = shift;
    my (%args) = @_;

    my $iter;
    if ( $args{load_args} ) {
        my $class = $app->model('tag');
        $iter = $class->load_iter( @{ $args{load_args} } );
    }
    elsif ( $args{iter} ) {
        $iter = $args{iter};
    }
    elsif ( $args{items} ) {
        $iter = sub { shift @{ $args{items} } };
    }
    return [] unless $iter;

    my $param   = $args{param} || {};
    my $blog_id = $app->query->param('blog_id');
    my $pkg     = $args{'package'};

    my @data;
    while ( my $tag = $iter->() ) {
        my $count = $pkg->tagged_count(
                              $tag->id,
                              {
                                ( $blog_id ? ( blog_id => $blog_id ) : () ),
                                ( $pkg =~ m/asset/i ? ( class => '*' ) : () )
                              }
        );
        $count ||= 0;
        my $row = {
                    tag_id    => $tag->id,
                    tag_name  => $tag->name,
                    tag_count => $count,
                    object    => $tag,
        };
        push @data, $row;
    }
    return [] unless @data;

    $param->{tag_table}[0]{object_loop} = \@data;
    $app->load_list_actions( 'tag', $param->{tag_table}[0] );
    $param->{object_loop} = $param->{tag_table}[0]{object_loop};
} ## end sub build_tag_table

1;

__END__

=head1 NAME

MT::CMS::Tag

=head1 METHODS

=head2 add_tags_to_assets

=head2 add_tags_to_entries

=head2 build_tag_table

=head2 can_delete

=head2 js_recent_entries_for_tag

=head2 js_tag_check

=head2 js_tag_list

=head2 list

=head2 list_tag_for

=head2 post_delete

=head2 remove_tags_from_assets

=head2 remove_tags_from_entries

=head2 rename_tag

=head1 AUTHOR & COPYRIGHT

Please see L<MT/AUTHOR & COPYRIGHT>.

=cut
