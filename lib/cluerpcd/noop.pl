#!perl
name => "noop",

access => "all",

func => sub {
	return {success, msg => "Nothing happens."};
};
