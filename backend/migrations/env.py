from alembic import context
from sqlalchemy import create_engine, pool

from lynveris.config import Settings
from lynveris.database import Base

config = context.config
target_metadata = Base.metadata
url = Settings().database_url
if context.is_offline_mode():
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()
else:
    supplied_connection = config.attributes.get("connection")

    def migrate(connection):
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()

    if supplied_connection is not None:
        migrate(supplied_connection)
    else:
        engine = create_engine(url, poolclass=pool.NullPool)
        with engine.connect() as connection:
            migrate(connection)
