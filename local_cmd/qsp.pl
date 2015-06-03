#
# qsp qtc telegrams per call
#
# Copyright (c) 2015 - Hans Freitag
#
#
my ($self, $line) = @_;
my @out;

if ( ! $main::qtc_root ) { return (1, $self->msg('qtcunconf')); }

my ($call, @refnums)=split(/\s+/, $line);

if ( $call =~ /^..$/ ) { 
	# I guess there is no call and call is a refnum
	push @refnums, $call; 
	$call=$self->call;
}
$call=$self->{qtc_query}->allowed_letters_for_call(lc($call));


## send qsp 
foreach my $ref (@refnums) {
#	print STDERR "Telegram by ref\n";
	my $telegram=$self->{qtc_query}->telegram_by_refnum($ref, $call); 
	if ( ! $telegram ) { push @out, "$ref not found for $call"; next; }
	push @out, "qsp $ref to $call";
	# we have a telegram, let us qsp.... 
	$self->{qtc_publish}->qsp(
		to=>$call,
		msg=>$telegram, 
		set_of_comment=>"dxspider call ".$self->{qtc_query}->allowed_letters_for_telegram(lc($self->call)),
	); 
}

return (1, @out);
