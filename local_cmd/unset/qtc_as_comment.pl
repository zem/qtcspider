#
# unset the gtk flag
#
# Copyright (c) 2006 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @out;
$self->user->wantqtc_as_comment(0);
push @out, $self->msg('qtc_as_commentu', $self->call);
return (1, @out);
