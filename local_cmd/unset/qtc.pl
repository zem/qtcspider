#
# unset the qtc flag 
#
# Copyright (c) 2015 - Hans Freitag
#
#
#


my ($self, $line) = @_;
my @out;
$self->user->wantqtc(0);
push @out, $self->msg('qtcu', $self->call);
return (1, @out);
