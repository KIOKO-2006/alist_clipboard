#!/bin/bash
# Simple script to create .env file from template

if [ -f ".env" ]; then
    echo "Warning: .env file already exists. Do you want to overwrite it? (y/n)"
    read -r answer
    if [ "$answer" != "y" ]; then
        echo "Setup cancelled."
        exit 1
    fi
fi

cp .env.example .env
echo ".env file created from template."
echo "Please edit .env with your Alist server details."
echo "You can run: nano .env"
