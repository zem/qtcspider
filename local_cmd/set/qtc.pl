#
# set the qtc flag 
#
# Copyright (c) 2015 - Hans Freitag
#
#
#

my ($self, $line) = @_;
my @out;
$self->user->wantqtc(1);
push @out, $self->msg('qtcs', $self->call);
if ( ! $main::qtc_root ) { push @out, "there is no QTC-NET configured on this spider"; }
return (1, @out);
