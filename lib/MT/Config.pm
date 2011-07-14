# Movable Type (r) Open Source (C) 2001-2010 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id$

package MT::Config;
use strict;
use base qw( MT::Object );

__PACKAGE__->install_properties( {
       column_defs =>
         { 'id' => 'integer not null auto_increment', 'data' => 'text', },
       primary_key => 'id',
       datasource  => 'config',

       # Added to eliminate overly aggressive caching of the config object
       # under persistent webserver environments.
       # Details at https://movabletype.fogbugz.com/?100356
       cacheable => 0,
    }
);

sub class_label {
    MT->translate("Configuration");
}

sub class_label_plural {
    MT->translate("Configuration");
}

1;
__END__

=head1 NAME

MT::Config - Installation-wide configuration data.

=head1 AUTHOR & COPYRIGHT

Please see L<MT/AUTHOR & COPYRIGHT>.

=cut
