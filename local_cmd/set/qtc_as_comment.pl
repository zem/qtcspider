#
# set the qtc_as_comment flag 
#
# Copyright (c) 2015 - Hans Freitag
#
#
#

my ($self, $line) = @_;
my @out;
$self->user->wantqtc_as_comment(1);
push @out, $self->msg('qtc_as_comments', $self->call);
return (1, @out);
