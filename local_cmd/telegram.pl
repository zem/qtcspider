#
# send a telegram
#
# Copyright (c) 2015 - Hans Freitag
#
#

my ($self, $line) = @_;
my $from_call=substr($line, 0, index($line, " ")); 
$line = substr($line, index($line, " ")+1);
my $to_call=substr($line, 0, index($line, " ")); 
$line = substr($line, index($line, " ")+1);

eval {
	$self->{qtc_publish}->telegram(
		from=>$self->{qtc_publish}->allowed_letters_for_call(lc($from_call)),
		to=>$self->{qtc_publish}->allowed_letters_for_call(lc($to_call)),
		telegram=>$self->{qtc_publish}->allowed_letters_for_telegram($line), 
	); 
};

return (1, "submitting telegram from $from_call to $to_call", $@);

