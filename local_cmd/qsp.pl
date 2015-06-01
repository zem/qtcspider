#
# set the qtc flag 
#
# Copyright (c) 2006 - Dirk Koopman
#
#
#

my ($self, $line) = @_;
my @out;

my ($call, @refnums)=split(/\s+/, $line);

if ( $call =~ /^..$/ ) { 
	# I guess there is no call and call is a refnum
	push @refnum, $call; 
	$call=$self->call;
}

# send qsp 
foreach my $ref (@refnums) {
	my $telegram=$self->{qtc_query}->telegram_by_refnum($ref, lc($call)); 
	if ( ! $telegram ) { next; }
	# we have a telegram, let us qsp.... 
	$self->{qtc_publish}->qsp(
		to=>lc($to_call),
		msg=>$telegram, 
		set_of_comments=>"dxspider call ".$self->{qtc_query}->allowed_letters_for_telegram(lc($call)),
	); 
}

return (1, @out);
