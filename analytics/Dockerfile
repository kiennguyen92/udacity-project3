FROM public.ecr.aws/docker/library/python:3.9.18

ENV DB_USERNAME="admin"
ENV DB_USERNAME="admin"

COPY requirements.txt requirements.txt

RUN pip install -r requirements.txt

# Expose the port that the application listens on.
EXPOSE 8000

COPY . .

# Run the application.
CMD gunicorn 'app:app' --bind=0.0.0.0:8000
