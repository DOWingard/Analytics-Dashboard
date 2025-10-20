import random

def get_live_data():
    return {
        "cpu_usage": random.random() * 100,
        "users_online": random.randint(10, 1000),
        "sales": random.uniform(1000, 5000)
    }
