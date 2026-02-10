from flask import Flask, jsonify
import os
import mysql.connector

app = Flask(__name__)

@app.route('/api/data')
def get_data():
    db_host = os.environ.get('DB_HOST')
    db_pass = os.environ.get('DB_PASS')

    if not db_host:
        return jsonify({"error": "DB_HOST environment variable is missing"}), 500

    try:
        conn = mysql.connector.connect(
            host=db_host,
            user='adminuser',
            password=db_pass,
            database='labdb'
        )
        cursor = conn.cursor()
        cursor.execute("SELECT 'Hello Lab-commit 10'") 
        result = cursor.fetchone()
        conn.close()
        return jsonify({"message": result[0]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)