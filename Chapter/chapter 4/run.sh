#!/bin/sh

nasm -I ../include/ -o ./loader.bin ../loader.S
nasm -I ../include/ -o ./mbr.bin ../mbr.S
dd if=./mbr.bin of=/home/buzzlight/bochs/hd60M.img bs=512 count=1 conv=notrunc
dd if=./loader.bin of=/home/buzzlight/bochs/hd60M.img bs=512 count=2 seek=2 conv=notrunc
echo ok!
