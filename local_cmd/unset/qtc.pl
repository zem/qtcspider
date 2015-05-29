#
# unset the gtk flag
#
# Copyright (c) 2006 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @out;
$self->user->wantqtc(0);
push @out, $self->msg('qtcu', $self->call);
return (1, @out);
