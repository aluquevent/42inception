COMPOSE  := docker compose -f srcs/docker-compose.yml
ENV_FILE := srcs/.env

include $(ENV_FILE)

all: up

up: dirs
	$(COMPOSE) up -d --build

dirs:
	mkdir -p $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --rmi all -v

fclean: clean
	sudo rm -rf $(DATA_PATH)

re: fclean all

.PHONY: all up dirs down clean fclean re


