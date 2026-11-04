FROM python:3.12-slim
WORKDIR /app
COPY api/ /app/
RUN mkdir -p /app/data && chown -R nobody:nogroup /app/data
ENV PORT=8080 HOST=0.0.0.0
EXPOSE 8080
USER nobody
CMD ["python", "app.py"]
