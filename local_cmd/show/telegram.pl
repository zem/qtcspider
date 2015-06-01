#
# shows qtc telegrams per call
#
# Copyright (c) 2015 - Hans Freitag
#
#
#
my ($self, $line) = @_;
my @out;

my ($call, $type, $anz, $offset)=split(/\s+/, $line);

if ( $call =~ /^(new)|(timeline_new)|(timeline)|(all)|(sent)$/ ) { 
	# $call is a type
	$offset=$anz; 
	$anz=$type; 
	$type=$call; 
	$call=$self->call();
}
if ( ! $call ) { $call=$self->call(); }

foreach my $msg ($self->{qtc_query}->list_telegrams(lc($call), $type, int($anz), int($offset))) {
	#push @out, $msg->filename; 
	push @out, $self->format_telegram($msg); 
}

return (1, @out);
