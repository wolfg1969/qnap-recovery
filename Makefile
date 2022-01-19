all:

pc1:
	gcc -o pc1 pc1.c
%.tgz: %.img pc1
	./pc1 d QNAPNASVERSION4 $< $@

build-dep:
	apt install libjson-pp-perl kpartx

