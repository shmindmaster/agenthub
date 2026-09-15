import React, { useState } from "react";
import {
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";

export default function App() {
  const [draft, setDraft] = useState("");
  const [result, setResult] = useState("Waiting for input");

  return (
    <SafeAreaView style={styles.safeArea}>
      <View style={styles.card}>
        <Text accessibilityRole="header" style={styles.title}>
          Mobile Lab Smoke
        </Text>
        <Text accessibilityLabel="lab-status" style={styles.status}>
          Ready on this simulator
        </Text>
        <TextInput
          accessibilityLabel="message-input"
          autoCapitalize="none"
          onChangeText={setDraft}
          placeholder="Type a smoke-test message"
          style={styles.input}
          testID="message-input"
          value={draft}
        />
        <Pressable
          accessibilityLabel="submit-message"
          accessibilityRole="button"
          onPress={() => setResult(draft ? `Echo: ${draft}` : "Echo: empty")}
          style={styles.button}
          testID="submit-message"
        >
          <Text style={styles.buttonText}>Submit message</Text>
        </Pressable>
        <Text accessibilityLabel="echo-result" style={styles.result} testID="echo-result">
          {result}
        </Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: "#eef2ff",
    justifyContent: "center",
  },
  card: {
    margin: 24,
    padding: 24,
    borderRadius: 20,
    backgroundColor: "#ffffff",
    gap: 16,
  },
  title: {
    color: "#172554",
    fontSize: 28,
    fontWeight: "700",
  },
  status: {
    color: "#166534",
    fontSize: 16,
  },
  input: {
    borderColor: "#94a3b8",
    borderRadius: 12,
    borderWidth: 1,
    fontSize: 16,
    padding: 14,
  },
  button: {
    alignItems: "center",
    backgroundColor: "#1d4ed8",
    borderRadius: 12,
    padding: 14,
  },
  buttonText: {
    color: "#ffffff",
    fontSize: 16,
    fontWeight: "600",
  },
  result: {
    color: "#0f172a",
    fontSize: 18,
  },
});
