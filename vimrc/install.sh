#!/bin/bash

echo "Installing..."

mkdir -p ~/.vim;
cp -r vim/* ~/.vim;

cp vimrc ~/.vimrc;
cp vimrc.after ~/.vimrc.after;
cp vimrc.before ~/.vimrc.before;

echo "Done installing";
