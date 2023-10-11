
default:
	zig run src/main.zig
	gcc -g output.S -o program

run: default
	./program

.PHONY:
	clean

clean:
	rm -f output.S program
