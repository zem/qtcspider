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
if ( ! $main::qtc_root ) { push @out, $self->msg('qtcunconf'); }
return (1, @out);
