#
# set the qtc flag 
#
# Copyright (c) 2006 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @out;
$self->user->wantqtc(1);
push @out, $self->msg('qtcs', $self->call);
return (1, @out);
