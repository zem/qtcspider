#
# qsp qtc telegrams per call
#
# Copyright (c) 2015 - Hans Freitag
#
#
my ($self, $line) = @_;
my @out;

push @out, "qsp $line\n";

#my ($call, @refnums)=split(/\s+/, $line);
#
#if ( $call =~ /^..$/ ) { 
#	# I guess there is no call and call is a refnum
#	push @refnum, $call; 
#	$call=$self->call;
#}

#print STDERR "qsp $call @refnum\n";

## send qsp 
#foreach my $ref (@refnums) {
#	print STDERR "Telegram by ref\n";
#	my $telegram=$self->{qtc_query}->telegram_by_refnum($ref, lc($call)); 
#	if ( ! $telegram ) { next; }
#	print STDERR "publish $telegram\n";
#	# we have a telegram, let us qsp.... 
#	$self->{qtc_publish}->qsp(
#		to=>lc($to_call),
#		msg=>$telegram, 
#		set_of_comment=>"dxspider call ".$self->{qtc_query}->allowed_letters_for_telegram(lc($call)),
#	); 
#}

return (1, @out);
