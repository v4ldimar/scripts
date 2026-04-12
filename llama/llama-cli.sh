#/bin/bash
if [ -z "$1" ]; then
	echo "Usage: $0 <model> [llama cli options]"
	exit 1
fi

model="$1"
shift

/home/alabot/llama.cpp/build/bin/llama-cli --model /home/alabot/models/$model "$@"
