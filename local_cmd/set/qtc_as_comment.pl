#
# set the qtc flag 
#
# Copyright (c) 2006 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @out;
$self->user->wantqtc_as_comment(1);
push @out, $self->msg('qtc_as_comments', $self->call);
return (1, @out);
